import cv2
import numpy as np
import os
import json
import math
import logging
from collections import Counter
from datetime import datetime
from typing import Optional, List

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from tensorflow.keras.models import load_model
from pydantic import BaseModel

# ─────────────────────────────────────────────
# CONFIGURATION DES LOGS
# ─────────────────────────────────────────────
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="API Détection Maladies Plantes",
    description="API basée sur MobileNetV2 pour détecter les maladies des plantes.",
    version="3.0.0"
)

# ─────────────────────────────────────────────
# CORS
# ─────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─────────────────────────────────────────────
# 1. CHARGEMENT DU MODÈLE AU DÉMARRAGE
# ─────────────────────────────────────────────
dataset_type = "color"
model_path   = f"./models/mobilenetv2_{dataset_type}.h5"

model: object = None
class_names: List[str] = []

@app.on_event("startup")
async def load_model_on_startup():
    global model, class_names
    try:
        if not os.path.exists(model_path):
            logger.error(f"❌ Fichier modèle introuvable : {model_path}")
            raise FileNotFoundError(f"Modèle introuvable : {model_path}")

        model = load_model(model_path)
        logger.info(f"✅ Modèle chargé depuis : {model_path}")

        num_classes = model.output_shape[-1]
        logger.info(f"ℹ️  Le modèle a {num_classes} classes en sortie.")

        classes_file = f"./models/classes_{dataset_type}.txt"
        if os.path.exists(classes_file):
            with open(classes_file, "r") as f:
                class_names = [line.strip() for line in f if line.strip()]
            logger.info(f"✅ Classes chargées : {class_names}")
            if len(class_names) != num_classes:
                logger.warning(
                    f"⚠️  {len(class_names)} classes dans le fichier "
                    f"mais {num_classes} dans le modèle."
                )
        else:
            class_names = [f"Classe_{i}" for i in range(num_classes)]
            logger.warning(f"⚠️  '{classes_file}' introuvable. Noms génériques utilisés.")

    except Exception as e:
        logger.error(f"❌ Erreur au chargement du modèle : {e}")
        model = None


# ─────────────────────────────────────────────
# 2. PRÉTRAITEMENT IMAGE
# ─────────────────────────────────────────────
def preprocess_image(image_bytes: bytes) -> np.ndarray:
    np_array = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(np_array, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(
            "Le fichier envoyé n'est pas une image valide "
            "(formats acceptés : JPG, PNG, BMP, WebP)."
        )
    img = cv2.resize(img, (224, 224))
    img = img / 255.0
    img = np.expand_dims(img, axis=0)
    return img


# ─────────────────────────────────────────────
# FONCTION UTILITAIRE : PRÉDIRE UNE IMAGE
# ─────────────────────────────────────────────
def _predire(image_bytes: bytes) -> dict:
    """Prétraite et prédit une image. Retourne un dict avec maladie, confiance, top3."""
    img = preprocess_image(image_bytes)
    pred = model.predict(img, verbose=0)

    predicted_index = int(np.argmax(pred))
    confidence      = float(np.max(pred))
    predicted_class = (
        class_names[predicted_index]
        if predicted_index < len(class_names)
        else f"Classe_{predicted_index}"
    )

    top3_indices = np.argsort(pred[0])[::-1][:3]
    top3 = [
        {
            "classe": class_names[i] if i < len(class_names) else f"Classe_{i}",
            "probabilite": f"{float(pred[0][i]) * 100:.2f}%"
        }
        for i in top3_indices
    ]

    return {
        "maladie":   predicted_class,
        "confiance": f"{confidence * 100:.2f}%",
        "confiance_float": confidence,
        "top3":      top3,
    }


# ─────────────────────────────────────────────
# 3. ENDPOINT — PRÉDICTION SIMPLE
# ─────────────────────────────────────────────
@app.post("/predict")
async def predict_image(file: UploadFile = File(...)):
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Le modèle n'est pas disponible. Vérifiez les logs du serveur."
        )

    allowed_types = [
        "image/jpeg", "image/jpg", "image/png",
        "image/bmp", "image/webp", "application/octet-stream",
    ]
    if file.content_type and file.content_type not in allowed_types:
        raise HTTPException(
            status_code=415,
            detail=f"Type non supporté : '{file.content_type}'."
        )

    image_bytes = await file.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image trop lourde (max 10 Mo).")

    try:
        img = preprocess_image(image_bytes)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    try:
        resultat = _predire(image_bytes)
    except Exception as e:
        logger.error(f"❌ Erreur prédiction : {e}")
        raise HTTPException(status_code=500, detail="Erreur interne lors de la prédiction.")

    logger.info(f"✅ Prédiction : {resultat['maladie']} ({resultat['confiance']})")

    return {
        "status":    "success",
        "maladie":   resultat["maladie"],
        "confiance": resultat["confiance"],
        "top3":      resultat["top3"],
    }


# ─────────────────────────────────────────────
# 4. ENDPOINT — PRÉDICTION MULTI-PHOTOS
# ─────────────────────────────────────────────
@app.post("/predict_multi")
async def predict_multi(files: List[UploadFile] = File(...)):
    """
    Analyse 1 à 5 photos en une seule requête.
    Retourne les résultats individuels de chaque photo.
    Flutter se charge ensuite de la synthèse via Groq.
    """
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Le modèle n'est pas disponible."
        )

    if len(files) == 0:
        raise HTTPException(status_code=400, detail="Au moins une photo est requise.")

    if len(files) > 5:
        raise HTTPException(status_code=400, detail="Maximum 5 photos autorisées.")

    resultats = []

    for i, file in enumerate(files):
        try:
            image_bytes = await file.read()

            # ✅ Vérification taille
            if len(image_bytes) > 10 * 1024 * 1024:
                resultats.append({
                    "photo":  i + 1,
                    "status": "error",
                    "detail": "Image trop lourde (max 10 Mo)."
                })
                continue

            resultat = _predire(image_bytes)

            resultats.append({
                "photo":    i + 1,
                "fichier":  file.filename or f"photo_{i+1}.jpg",
                "status":   "success",
                "maladie":  resultat["maladie"],
                "confiance": resultat["confiance"],
                "confiance_float": resultat["confiance_float"],
                "top3":     resultat["top3"],
            })
            logger.info(f"✅ Photo {i+1} : {resultat['maladie']} ({resultat['confiance']})")

        except ValueError as e:
            resultats.append({
                "photo":  i + 1,
                "status": "error",
                "detail": str(e)
            })
        except Exception as e:
            logger.error(f"❌ Erreur photo {i+1} : {e}")
            resultats.append({
                "photo":  i + 1,
                "status": "error",
                "detail": "Erreur interne lors de l'analyse."
            })

    # ✅ Résumé global
    succes    = [r for r in resultats if r["status"] == "success"]
    erreurs   = [r for r in resultats if r["status"] == "error"]
    maladies  = [r["maladie"] for r in succes]
    compteur  = Counter(maladies)
    maladie_dominante = compteur.most_common(1)[0][0] if compteur else "Inconnue"
    confiance_moy = (
        sum(r["confiance_float"] for r in succes) / len(succes)
        if succes else 0.0
    )

    logger.info(f"✅ Multi-predict : {len(succes)}/{len(files)} photos OK — Dominante : {maladie_dominante}")

    return {
        "status":             "success",
        "nombre_photos":      len(files),
        "analyses_reussies":  len(succes),
        "analyses_echouees":  len(erreurs),
        "maladie_dominante":  maladie_dominante,
        "confiance_moyenne":  f"{confiance_moy * 100:.2f}%",
        "resultats":          resultats,
    }


# ─────────────────────────────────────────────
# 5. ENDPOINT — HEALTH CHECK
# ─────────────────────────────────────────────
@app.get("/health")
async def health_check():
    return {
        "status":         "ok" if model is not None else "error",
        "modele_charge":  model is not None,
        "nombre_classes": len(class_names),
        "classes":        class_names,
    }


# ─────────────────────────────────────────────
# 6. MODÈLES PYDANTIC — GÉOLOCALISATION
# ─────────────────────────────────────────────
class AnalyseGeoIn(BaseModel):
    maladie:   str
    confiance: float
    top3:      str
    latitude:  float
    longitude: float
    date:      Optional[str] = None

class AnalyseGeoOut(BaseModel):
    id:        int
    maladie:   str
    confiance: float
    latitude:  float
    longitude: float
    date:      str


# ─────────────────────────────────────────────
# 7. BASE DE DONNÉES GEO (fichier JSON local)
# ─────────────────────────────────────────────
GEO_DB_FILE = "geo_analyses.json"

def _lire_geo_db() -> List[dict]:
    if not os.path.exists(GEO_DB_FILE):
        return []
    with open(GEO_DB_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def _ecrire_geo_db(data: List[dict]) -> None:
    with open(GEO_DB_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R    = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a    = (math.sin(dlat / 2) ** 2 +
            math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
            math.sin(dlon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ─────────────────────────────────────────────
# 8. ENDPOINT — POST /analyses/geo
# ─────────────────────────────────────────────
@app.post("/analyses/geo", response_model=AnalyseGeoOut)
async def soumettre_analyse_geo(analyse: AnalyseGeoIn):
    db        = _lire_geo_db()
    nouvel_id = (max((a["id"] for a in db), default=0)) + 1

    entree = {
        "id":        nouvel_id,
        "maladie":   analyse.maladie,
        "confiance": round(analyse.confiance, 4),
        "latitude":  analyse.latitude,
        "longitude": analyse.longitude,
        "date":      analyse.date or datetime.now().isoformat(),
    }
    db.append(entree)
    _ecrire_geo_db(db)
    return entree


# ─────────────────────────────────────────────
# 9. ENDPOINT — GET /analyses/geo
# ─────────────────────────────────────────────
@app.get("/analyses/geo", response_model=List[AnalyseGeoOut])
async def lister_analyses_geo(
    maladie:  Optional[str]   = None,
    lat:      Optional[float] = None,
    lon:      Optional[float] = None,
    rayon_km: Optional[float] = None,
):
    db = _lire_geo_db()

    if maladie:
        db = [a for a in db if maladie.lower() in a["maladie"].lower()]

    if lat is not None and lon is not None and rayon_km is not None:
        db = [
            a for a in db
            if _distance_km(lat, lon, a["latitude"], a["longitude"]) <= rayon_km
        ]

    return db


# ─────────────────────────────────────────────
# 10. ENDPOINT — GET /analyses/geo/stats
# ─────────────────────────────────────────────
@app.get("/analyses/geo/stats")
async def stats_epidemie(
    lat:      float,
    lon:      float,
    rayon_km: float = 10.0,
    seuil:    int   = 3,
):
    db = _lire_geo_db()

    dans_zone = [
        a for a in db
        if "sain" not in a["maladie"].lower()
        and _distance_km(lat, lon, a["latitude"], a["longitude"]) <= rayon_km
    ]

    compteur  = Counter(a["maladie"] for a in dans_zone)
    epidemies = [
        {"maladie": m, "nombre_cas": n, "alerte": n >= seuil}
        for m, n in compteur.most_common()
    ]

    return {
        "position":  {"lat": lat, "lon": lon},
        "rayon_km":  rayon_km,
        "total_cas": len(dans_zone),
        "epidemies": epidemies,
    }


# ─────────────────────────────────────────────
# 11. GESTIONNAIRE D'ERREURS GLOBAL
# ─────────────────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"❌ Erreur non gérée : {exc}")
    return JSONResponse(
        status_code=500,
        content={"status": "error", "detail": "Erreur interne inattendue."}
    )