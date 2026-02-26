"""
Nutrition analyzer for HealthClaw.

Routes food analysis requests through the OpenClaw gateway using
the sessions_send RPC, which gives us full LLM access including vision.
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from typing import Any

from database import store_meal_entry
from models import (
    FoodItem,
    NutrientDetail,
    NutritionAnalysisResponse,
    NutritionTotals,
)

# Full path to openclaw CLI
OPENCLAW_BIN = os.getenv("OPENCLAW_BIN", "/home/lars/.npm-global/bin/openclaw")
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


async def _call_agent(prompt: str, image_base64: str | None = None, image_mime_type: str | None = None) -> str:
    """
    Call an OpenClaw agent via CLI to get an LLM response.
    For images: saves to a temp file and instructs the agent to use the image tool.
    Runs in a thread pool to avoid blocking the async event loop.
    """
    def _run():
        session_id = f"nutrition-{uuid.uuid4().hex[:8]}"
        temp_image_path = None

        try:
            # If image provided, save to temp file for the agent to read
            if image_base64:
                ext = "jpg"
                if image_mime_type and "png" in image_mime_type:
                    ext = "png"
                temp_image_path = f"/tmp/healthclaw-food-{session_id}.{ext}"
                with open(temp_image_path, "wb") as f:
                    f.write(base64.b64decode(image_base64))

                # Prepend image analysis instruction
                prompt_with_image = (
                    f"First, use the image tool to analyze the food photo at {temp_image_path}. "
                    f"Then respond to this request:\n\n{prompt}"
                )
            else:
                prompt_with_image = prompt

            env = os.environ.copy()
            env["OPENCLAW_GATEWAY_TOKEN"] = GATEWAY_TOKEN
            env["PATH"] = "/home/lars/.npm-global/bin:" + env.get("PATH", "")

            result = subprocess.run(
                [
                    OPENCLAW_BIN, "agent",
                    "--session-id", session_id,
                    "--json",
                    "-m", prompt_with_image,
                    "--timeout", "120",
                ],
                capture_output=True,
                text=True,
                env=env,
                timeout=150,
            )

            if result.returncode != 0:
                raise RuntimeError(f"Agent call failed (code {result.returncode}): {result.stderr[:500]}")

            output = result.stdout.strip()
            try:
                data = json.loads(output)
                result_obj = data.get("result", data)
                payloads = result_obj.get("payloads", [])
                if payloads:
                    return payloads[0].get("text", output)
                payloads = data.get("payloads", [])
                if payloads:
                    return payloads[0].get("text", output)
                return output
            except json.JSONDecodeError:
                return output
        finally:
            # Clean up temp image
            if temp_image_path and os.path.exists(temp_image_path):
                os.unlink(temp_image_path)

    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _run)


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

    raise ValueError(f"Could not extract JSON from agent response: {text[:300]}")


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

    # If an image was provided, adjust the description
    if image_base64:
        if text and text.strip():
            description = f"{text} (also see the attached food photo for details)"
        else:
            description = "See the attached food photo. Identify all visible food items and estimate portions."
        prompt = ANALYSIS_PROMPT_TEMPLATE.format(description=description)

    # Call agent (handles both text-only and image analysis)
    raw_response = await _call_agent(prompt, image_base64, image_mime_type)

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

    for sample in healthkit_samples:
        ident = sample.get("identifier", "")
        if ident in hk_name_map:
            name, unit = hk_name_map[ident]
            all_nutrients.append({
                "name": name,
                "amount": float(sample.get("value", 0)),
                "unit": unit,
            })

    # Store in DB
    food_items_json_str = json.dumps(data.get("food_items", []))
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
        food_items_json=food_items_json_str,
    )

    return NutritionAnalysisResponse(
        meal_id=meal_id,
        timestamp=now,
        description=description,
        food_items=food_items,
        totals=totals,
        healthkit_samples=healthkit_samples,
    )
