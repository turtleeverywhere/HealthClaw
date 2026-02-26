"""
Nutrition analyzer for HealthClaw.

Routes food analysis requests through the OpenClaw gateway agent,
which has access to Anthropic Claude with vision capabilities.
"""

from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timezone
from typing import Any

from database import store_meal_entry
from models import (
    FoodItem,
    NutrientDetail,
    NutritionAnalysisResponse,
    NutritionTotals,
)

# OpenClaw gateway config
GATEWAY_TOKEN = os.getenv(
    "OPENCLAW_GATEWAY_TOKEN",
    "f8ac08ae67eb64d576d08214be062d2fc74c31849e8463cb",
)

ANALYSIS_PROMPT_TEMPLATE = """\
You are a nutritionist AI. Analyze the following food description and return ONLY a JSON object — no markdown, no explanation, just raw JSON.

Food description: {description}

Return this exact JSON structure (fill in real values):
{{
  "description": "<brief summary of what was eaten>",
  "food_items": [
    {{
      "name": "<food name>",
      "portion": "<portion description, e.g. '1 cup' or '200g'>",
      "calories": <number>,
      "protein_g": <number>,
      "carbs_g": <number>,
      "fat_g": <number>,
      "fiber_g": <number>,
      "sugar_g": <number>,
      "sodium_mg": <number>,
      "nutrients": [
        {{"name": "<nutrient>", "amount": <number>, "unit": "<unit>", "daily_value_pct": <number or null>}}
      ]
    }}
  ],
  "totals": {{
    "calories": <sum>,
    "protein_g": <sum>,
    "carbs_g": <sum>,
    "fat_g": <sum>,
    "fiber_g": <sum>,
    "sugar_g": <sum>,
    "sodium_mg": <sum>
  }},
  "healthkit_samples": [
    {{"identifier": "dietaryEnergyConsumed", "value": <kcal>, "unit": "kcal"}},
    {{"identifier": "dietaryProtein", "value": <g>, "unit": "g"}},
    {{"identifier": "dietaryCarbohydrates", "value": <g>, "unit": "g"}},
    {{"identifier": "dietaryFatTotal", "value": <g>, "unit": "g"}},
    {{"identifier": "dietaryFatSaturated", "value": <g>, "unit": "g"}},
    {{"identifier": "dietaryFiber", "value": <g>, "unit": "g"}},
    {{"identifier": "dietarySugar", "value": <g>, "unit": "g"}},
    {{"identifier": "dietarySodium", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryCholesterol", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryCalcium", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryIron", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryVitaminC", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryVitaminD", "value": <IU>, "unit": "IU"}},
    {{"identifier": "dietaryPotassium", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryMagnesium", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryVitaminA", "value": <IU>, "unit": "IU"}},
    {{"identifier": "dietaryVitaminB6", "value": <mg>, "unit": "mg"}},
    {{"identifier": "dietaryVitaminB12", "value": <mcg>, "unit": "mcg"}},
    {{"identifier": "dietaryFolate", "value": <mcg>, "unit": "mcg"}},
    {{"identifier": "dietaryZinc", "value": <mg>, "unit": "mg"}}
  ]
}}

Use your best nutritional knowledge to estimate values. Be realistic and accurate."""


def _call_agent(prompt: str, image_base64: str | None = None, image_mime_type: str | None = None) -> str:
    """
    Call the OpenClaw gateway agent (local mode) to get an LLM response.
    Returns the raw text response.
    """
    # Build the full message — if there's an image, include it as a data URL hint
    # (Note: openclaw agent CLI doesn't support inline images, so we include
    # the image description in the prompt if provided)
    message = prompt

    env = os.environ.copy()
    env["OPENCLAW_GATEWAY_TOKEN"] = GATEWAY_TOKEN

    result = subprocess.run(
        [
            "openclaw", "agent",
            "--agent", "coder",
            "--local",
            "--json",
            "-m", message,
            "--timeout", "60",
        ],
        capture_output=True,
        text=True,
        env=env,
        timeout=90,
    )

    if result.returncode != 0:
        raise RuntimeError(f"Agent call failed: {result.stderr[:500]}")

    # Parse the JSON response from openclaw agent --json
    try:
        data = json.loads(result.stdout)
        payloads = data.get("payloads", [])
        if payloads:
            return payloads[0].get("text", "")
        return result.stdout
    except json.JSONDecodeError:
        # If not valid JSON wrapper, return raw stdout
        return result.stdout.strip()


def _extract_json(text: str) -> dict:
    """Extract JSON object from agent response text."""
    text = text.strip()

    # Try direct parse first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try to find JSON block between ```json ... ``` or { ... }
    if "```json" in text:
        start = text.index("```json") + 7
        end = text.index("```", start)
        try:
            return json.loads(text[start:end].strip())
        except (json.JSONDecodeError, ValueError):
            pass

    if "```" in text:
        start = text.index("```") + 3
        end = text.index("```", start)
        try:
            return json.loads(text[start:end].strip())
        except (json.JSONDecodeError, ValueError):
            pass

    # Find the outermost { ... }
    brace_start = text.find("{")
    brace_end = text.rfind("}")
    if brace_start != -1 and brace_end != -1:
        try:
            return json.loads(text[brace_start : brace_end + 1])
        except json.JSONDecodeError:
            pass

    raise ValueError(f"Could not extract JSON from agent response: {text[:200]}")


async def analyze_nutrition(
    text: str,
    image_base64: str | None = None,
    image_mime_type: str | None = None,
) -> NutritionAnalysisResponse:
    """
    Analyze food from text description (and optional image) using Claude.
    Stores the result in the database and returns a structured response.
    """
    now = datetime.now(timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    timestamp_str = now.isoformat()

    # Build the analysis prompt
    prompt = ANALYSIS_PROMPT_TEMPLATE.format(description=text)

    # If an image was provided, note it in the prompt
    if image_base64:
        mime = image_mime_type or "image/jpeg"
        prompt = (
            f"I have provided a food image ({mime}) along with this description.\n\n"
            + prompt
        )

    # Call the agent
    raw_response = _call_agent(prompt, image_base64, image_mime_type)

    # Parse the structured JSON
    data = _extract_json(raw_response)

    # Build food items
    food_items: list[FoodItem] = []
    for item in data.get("food_items", []):
        nutrients = [
            NutrientDetail(
                name=n.get("name", ""),
                amount=float(n.get("amount", 0)),
                unit=n.get("unit", ""),
                daily_value_pct=n.get("daily_value_pct"),
            )
            for n in item.get("nutrients", [])
        ]
        food_items.append(
            FoodItem(
                name=item.get("name", "Unknown"),
                portion=item.get("portion", ""),
                calories=float(item.get("calories", 0)),
                protein_g=float(item.get("protein_g", 0)),
                carbs_g=float(item.get("carbs_g", 0)),
                fat_g=float(item.get("fat_g", 0)),
                fiber_g=float(item.get("fiber_g", 0)),
                sugar_g=float(item.get("sugar_g", 0)),
                sodium_mg=float(item.get("sodium_mg", 0)),
                nutrients=nutrients,
            )
        )

    # Build totals
    totals_raw = data.get("totals", {})
    totals = NutritionTotals(
        calories=float(totals_raw.get("calories", 0)),
        protein_g=float(totals_raw.get("protein_g", 0)),
        carbs_g=float(totals_raw.get("carbs_g", 0)),
        fat_g=float(totals_raw.get("fat_g", 0)),
        fiber_g=float(totals_raw.get("fiber_g", 0)),
        sugar_g=float(totals_raw.get("sugar_g", 0)),
        sodium_mg=float(totals_raw.get("sodium_mg", 0)),
    )

    healthkit_samples: list[dict[str, Any]] = data.get("healthkit_samples", [])
    description = data.get("description", text)

    # Flatten all nutrients for DB storage
    all_nutrients: list[dict] = []
    for item in food_items:
        for n in item.nutrients:
            all_nutrients.append({"name": n.name, "amount": n.amount, "unit": n.unit})

    # Also store the HealthKit samples as nutrients (for completeness)
    hk_name_map = {
        "dietaryEnergyConsumed": ("Energy", "kcal"),
        "dietaryProtein": ("Protein", "g"),
        "dietaryCarbohydrates": ("Carbohydrates", "g"),
        "dietaryFatTotal": ("Fat Total", "g"),
        "dietaryFatSaturated": ("Saturated Fat", "g"),
        "dietaryFiber": ("Fiber", "g"),
        "dietarySugar": ("Sugar", "g"),
        "dietarySodium": ("Sodium", "mg"),
        "dietaryCholesterol": ("Cholesterol", "mg"),
        "dietaryCalcium": ("Calcium", "mg"),
        "dietaryIron": ("Iron", "mg"),
        "dietaryVitaminC": ("Vitamin C", "mg"),
        "dietaryVitaminD": ("Vitamin D", "IU"),
        "dietaryPotassium": ("Potassium", "mg"),
        "dietaryMagnesium": ("Magnesium", "mg"),
        "dietaryVitaminA": ("Vitamin A", "IU"),
        "dietaryVitaminB6": ("Vitamin B6", "mg"),
        "dietaryVitaminB12": ("Vitamin B12", "mcg"),
        "dietaryFolate": ("Folate", "mcg"),
        "dietaryZinc": ("Zinc", "mg"),
    }
    seen_nutrients = {n["name"] for n in all_nutrients}
    for sample in healthkit_samples:
        ident = sample.get("identifier", "")
        if ident in hk_name_map:
            name, unit = hk_name_map[ident]
            if name not in seen_nutrients:
                all_nutrients.append({
                    "name": name,
                    "amount": float(sample.get("value", 0)),
                    "unit": unit,
                })
                seen_nutrients.add(name)

    # Store in DB
    meal_id = await store_meal_entry(
        date=date_str,
        timestamp=timestamp_str,
        description=description,
        analysis_json=raw_response,
        total_calories=totals.calories,
        total_protein_g=totals.protein_g,
        total_carbs_g=totals.carbs_g,
        total_fat_g=totals.fat_g,
        nutrients=all_nutrients,
    )

    return NutritionAnalysisResponse(
        meal_id=meal_id,
        timestamp=now,
        description=description,
        food_items=food_items,
        totals=totals,
        healthkit_samples=healthkit_samples,
    )
