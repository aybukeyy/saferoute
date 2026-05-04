#!/usr/bin/env python3
"""Generate N synthetic reports clustered around Beşiktaş hot zones and write
them to app/assets/seed_reports.json. Used for demo videos that need a dense
heatmap (real seed has only ~50 entries).

Hot zones loosely match the original 50-entry seed:
  - Akaretler         (41.045, 28.991)  harassment + violence (night)
  - Beşiktaş İskele   (41.041, 29.005)  theft (daytime)
  - Yıldız Park edge  (41.046, 29.012)  suspicious + vandalism (night)
plus a "scatter" tier across the broader Beşiktaş bbox so the heatmap reads
as a citywide signal, not three blobs.

Usage:
  python3 tools/gen_fake_reports.py --count 1000
"""

import argparse
import json
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BBOX_MIN_LNG, BBOX_MIN_LAT, BBOX_MAX_LNG, BBOX_MAX_LAT = 28.985, 41.040, 29.045, 41.080

HOT_ZONES = [
    {
        "name": "Akaretler",
        "center": (41.0451, 28.9912),
        "radius_deg": 0.0030,
        "weight": 14,
        "categories": [("harassment", 50), ("violence", 30), ("suspicious_activity", 20)],
        "night_bias": 0.85,
    },
    {
        "name": "Beşiktaş İskele",
        "center": (41.0418, 29.0048),
        "radius_deg": 0.0025,
        "weight": 12,
        "categories": [("theft", 60), ("harassment", 20), ("suspicious_activity", 20)],
        "night_bias": 0.30,
    },
    {
        "name": "Yıldız Park edge",
        "center": (41.0463, 29.0125),
        "radius_deg": 0.0035,
        "weight": 10,
        "categories": [("suspicious_activity", 40), ("vandalism", 35), ("violence", 15), ("theft", 10)],
        "night_bias": 0.75,
    },
    {
        "name": "Ortaköy",
        "center": (41.0460, 29.0270),
        "radius_deg": 0.0030,
        "weight": 8,
        "categories": [("theft", 40), ("harassment", 30), ("violence", 20), ("vandalism", 10)],
        "night_bias": 0.55,
    },
    {
        "name": "Çırağan",
        "center": (41.0432, 29.0185),
        "radius_deg": 0.0025,
        "weight": 7,
        "categories": [("theft", 45), ("suspicious_activity", 30), ("harassment", 25)],
        "night_bias": 0.45,
    },
    {
        "name": "Maçka Park",
        "center": (41.0480, 28.9985),
        "radius_deg": 0.0035,
        "weight": 8,
        "categories": [("suspicious_activity", 40), ("violence", 25), ("harassment", 20), ("vandalism", 15)],
        "night_bias": 0.80,
    },
    {
        "name": "Kadirgalar",
        "center": (41.0552, 29.0145),
        "radius_deg": 0.0040,
        "weight": 6,
        "categories": [("theft", 35), ("vandalism", 30), ("suspicious_activity", 35)],
        "night_bias": 0.60,
    },
    {
        "name": "Levent yolu",
        "center": (41.0650, 29.0050),
        "radius_deg": 0.0045,
        "weight": 5,
        "categories": [("theft", 40), ("vandalism", 25), ("suspicious_activity", 35)],
        "night_bias": 0.55,
    },
    {
        # Spread cluster around (41.070, 29.025) — broad scatter (~3 km
        # diameter) so the area glows as a region, not a single dot.
        "name": "Kuzey-doğu çevresi",
        "center": (41.0700, 29.0250),
        "radius_deg": 0.0120,
        "weight": 9,
        "categories": [
            ("theft", 30), ("harassment", 25), ("violence", 15),
            ("suspicious_activity", 20), ("vandalism", 10),
        ],
        "night_bias": 0.60,
    },
]

SCATTER_WEIGHT = 100 - sum(z["weight"] for z in HOT_ZONES)  # 30
RISK_DISTRIBUTION = [("low", 25), ("medium", 50), ("high", 25)]

TR_TEMPLATES = {
    "harassment": [
        "Bir kişi {place}'de bir kadını takip etti, kadın hızla uzaklaştı.",
        "{place} civarında sözlü taciz vardı, gece geç saatte oldu.",
        "İki erkek {place}'de bir grubu rahatsız etti, polis çağrıldı.",
        "Sarhoş bir adam {place}'de yoldan geçenlere laf attı.",
        "Bir kadın {place} yakınında takip edildiğini söyledi.",
    ],
    "violence": [
        "{place}'de iki kişi arasında kavga çıktı, biri yere düştü.",
        "Geç saatte {place}'de fiziksel kavga yaşandı, polis geldi.",
        "{place} civarında bar çıkışı kavga oldu, ambulans çağrıldı.",
        "Sarhoş grup {place}'de yumruklaştı, etraf dağıldı.",
    ],
    "theft": [
        "{place}'de cüzdanım çalındı, kalabalıktan farketmedim.",
        "Motorlu kapkaç oldu {place} yakınında, çantam kayboldu.",
        "{place}'de bir turist telefonunu kaptırdı.",
        "Yankesici grubu {place}'de iş başında, üç kişi cüzdan kaybetti.",
        "{place} köşesinde sırt çantam açılmış, eşyalarım yok.",
    ],
    "suspicious_activity": [
        "{place}'de iki adam saatlerce park etmiş arabada bekliyor.",
        "Şüpheli bir kişi {place} kenarında yoldan geçenleri durduruyor.",
        "Bir grup {place} çıkışında geç saatte amaçsızca dolaşıyor.",
        "Garip davranan biri {place}'de fotoğraf çekiyor.",
        "{place}'de bir paket terkedilmiş, polis aradım.",
    ],
    "vandalism": [
        "Sokak lambaları {place} kenarında kırılmış.",
        "{place} duvarına tehdit içeren yazılar yazılmış.",
        "Otobüs durağı camı {place}'de kırık, taze gibi görünüyor.",
        "Park bankları {place}'de parçalanmış.",
        "{place}'de park edilmiş arabaların lastikleri kesilmiş.",
    ],
}

EN_TEMPLATES = {
    "harassment": [
        "A man was following a woman near {place}, she walked fast to lose him.",
        "Verbal harassment reported around {place} late at night.",
        "Two men were shouting at women passing by {place}.",
        "Drunk individual catcalling people near {place}.",
        "Woman reported being followed near {place}.",
    ],
    "violence": [
        "Fight broke out between two people at {place}, one fell to the ground.",
        "Late-night physical altercation near {place}, police responded.",
        "Bar fight outside {place}, ambulance called.",
        "Drunk group brawl near {place}, bystanders dispersed.",
    ],
    "theft": [
        "Wallet stolen at {place}, didn't notice in the crowd.",
        "Motorcycle snatch theft near {place}, bag gone.",
        "Tourist had her phone snatched at {place}.",
        "Pickpocket gang working at {place}, three people lost wallets.",
        "Backpack opened at {place}, items missing.",
    ],
    "suspicious_activity": [
        "Two men in a parked car at {place} for hours.",
        "Suspicious person near {place} stopping passersby.",
        "Group loitering at {place} late night with no apparent purpose.",
        "Unusual person at {place} taking photos of strangers.",
        "Abandoned package at {place}, called police.",
    ],
    "vandalism": [
        "Street lights smashed near {place}.",
        "Threatening graffiti on the wall at {place}.",
        "Bus stop glass broken near {place}, looks fresh.",
        "Park benches vandalized at {place}.",
        "Tires of parked cars slashed near {place}.",
    ],
}

PLACES_TR = ["Akaretler", "Beşiktaş İskele", "Yıldız Park", "Çırağan", "Süleyman Seba", "Ortaköy"]
PLACES_EN = ["Akaretler", "Beşiktaş ferry terminal", "Yıldız Park", "Çırağan", "the side street", "Ortaköy"]


def weighted_choice(items):
    total = sum(w for _, w in items)
    r = random.uniform(0, total)
    upto = 0
    for value, weight in items:
        upto += weight
        if r <= upto:
            return value
    return items[-1][0]


def random_point_in_zone(zone):
    """Gaussian-ish distribution around the zone center, clipped to bbox."""
    lat0, lng0 = zone["center"]
    r = abs(random.gauss(0, zone["radius_deg"] / 2))
    theta = random.uniform(0, 6.283185307)
    lat = lat0 + r * (1 if random.random() < 0.5 else -1) * abs(random.gauss(0, 1))
    lng = lng0 + r * (1 if random.random() < 0.5 else -1) * abs(random.gauss(0, 1))
    # Clip to bbox.
    lat = max(BBOX_MIN_LAT, min(BBOX_MAX_LAT, lat))
    lng = max(BBOX_MIN_LNG, min(BBOX_MAX_LNG, lng))
    return lat, lng


def random_point_scatter():
    return (
        random.uniform(BBOX_MIN_LAT, BBOX_MAX_LAT),
        random.uniform(BBOX_MIN_LNG, BBOX_MAX_LNG),
    )


def random_timestamp(night_bias):
    """Pick an occurredAt in the last 7 days. `night_bias` weights the hour."""
    days_ago = random.uniform(0, 7)
    base = datetime.now(timezone.utc) - timedelta(days=days_ago)
    if random.random() < night_bias:
        hour = random.choice([20, 21, 22, 23, 0, 1, 2, 3])
    else:
        hour = random.choice([8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
    return base.replace(
        hour=hour, minute=random.randint(0, 59), second=random.randint(0, 59), microsecond=0
    )


def synth_text(category, place):
    if random.random() < 0.6:
        templates = TR_TEMPLATES[category]
        place_choices = PLACES_TR
    else:
        templates = EN_TEMPLATES[category]
        place_choices = PLACES_EN
    template = random.choice(templates)
    chosen_place = place if place in place_choices else random.choice(place_choices)
    return template.format(place=chosen_place)


def synth_explanation(category):
    return {
        "harassment": "Synthetic seed — harassment incident.",
        "violence": "Synthetic seed — physical altercation.",
        "theft": "Synthetic seed — theft / pickpocket.",
        "suspicious_activity": "Synthetic seed — suspicious behavior.",
        "vandalism": "Synthetic seed — property damage.",
    }[category]


def generate(count):
    reports = []
    weights = [(z, z["weight"]) for z in HOT_ZONES] + [(None, SCATTER_WEIGHT)]
    for _ in range(count):
        zone = weighted_choice(weights)
        if zone is None:
            lat, lng = random_point_scatter()
            night_bias = 0.4
            cat_dist = [("theft", 30), ("harassment", 25), ("suspicious_activity", 20),
                        ("vandalism", 15), ("violence", 10)]
            place = "Beşiktaş"
        else:
            lat, lng = random_point_in_zone(zone)
            night_bias = zone["night_bias"]
            cat_dist = zone["categories"]
            place = zone["name"]

        category = weighted_choice(cat_dist)
        risk_level = weighted_choice(RISK_DISTRIBUTION)
        occurred_at = random_timestamp(night_bias)
        reports.append({
            "text": synth_text(category, place),
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "occurredAt": occurred_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "category": category,
            "riskLevel": risk_level,
            "explanation": synth_explanation(category),
        })
    return reports


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--count", type=int, default=1000)
    p.add_argument("--out", default="app/assets/seed_reports.json")
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    random.seed(args.seed)
    reports = generate(args.count)

    payload = {
        "_comment": f"Synthetic seed generated by tools/gen_fake_reports.py "
                    f"(count={args.count}, seed={args.seed}). Clustered around "
                    f"Akaretler / Beşiktaş İskele / Yıldız Park, plus broader scatter.",
        "demoRegion": {
            "name": "İstanbul / Beşiktaş",
            "bbox": [BBOX_MIN_LNG, BBOX_MIN_LAT, BBOX_MAX_LNG, BBOX_MAX_LAT],
            "center": [41.060, 29.015],
            "defaultZoom": 14,
        },
        "reports": reports,
    }
    out = Path(args.out)
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    print(f"wrote {len(reports)} reports → {out}")


if __name__ == "__main__":
    main()
