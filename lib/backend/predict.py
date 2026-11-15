import tensorflow as tf
from tensorflow.keras.models import load_model
import numpy as np
import cv2
import sys
import os

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
dataset_type = "color"
model_path = f"./models/mobilenetv2_{dataset_type}.h5"
classes_file = f"./models/classes_{dataset_type}.txt"

# ─────────────────────────────────────────────
# CHARGEMENT DU MODÈLE
# ─────────────────────────────────────────────
if not os.path.exists(model_path):
    print(f"❌ Modèle introuvable : {model_path}")
    sys.exit()

print("⏳ Chargement du modèle...")
model = load_model(model_path)
print(f"✅ Modèle chargé ({model.output_shape[-1]} classes)")

# ─────────────────────────────────────────────
# CHARGEMENT DES CLASSES
# ─────────────────────────────────────────────
if os.path.exists(classes_file):
    with open(classes_file, "r") as f:
        class_names = [line.strip() for line in f.readlines() if line.strip()]
    print(f"✅ {len(class_names)} classes chargées depuis {classes_file}")
else:
    # Fallback avec les 15 classes connues
    class_names = [
    "Pommier — Tavelure du pommier",
    "Pommier — Pourriture noire",
    "Pommier — Rouille du pommier",
    "Pommier — Sain",
    "Maïs — Tache foliaire à Cercospora",
    "Maïs — Rouille commune",
    "Maïs — Brûlure du nord",
    "Maïs — Sain",
    "Vigne — Pourriture noire",
    "Vigne — Esca (Rougeot parasite)",
    "Vigne — Brûlure des feuilles",
    "Vigne — Saine",
    "Tomate — Tache bactérienne",
    "Tomate — Saine",
    "Tomate — Moisissure des feuilles",
]
    print(f"⚠️  Fichier classes introuvable, utilisation des classes par défaut ({len(class_names)} classes)")

# ─────────────────────────────────────────────
# VÉRIFICATION DE L'ARGUMENT IMAGE
# ─────────────────────────────────────────────
if len(sys.argv) < 2:
    print("Usage: python predict.py <chemin_de_l_image>")
    sys.exit()

img_path = sys.argv[1]

if not os.path.exists(img_path):
    print(f"❌ Image introuvable : {img_path}")
    sys.exit()

# ─────────────────────────────────────────────
# CHARGEMENT ET PRÉTRAITEMENT DE L'IMAGE
# ─────────────────────────────────────────────
img = cv2.imread(img_path)

# ✅ Vérification que l'image est bien lue
if img is None:
    print(f"❌ Impossible de lire l'image : {img_path}")
    print("   Vérifiez que le fichier est une image valide (JPG, PNG, BMP).")
    sys.exit()

# ✅ Conversion BGR → RGB (OpenCV lit en BGR, le modèle attend RGB)
img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
img = cv2.resize(img, (224, 224))
img = img / 255.0
img = np.expand_dims(img, axis=0)

# ─────────────────────────────────────────────
# PRÉDICTION
# ─────────────────────────────────────────────
print("🔍 Analyse en cours...")
pred = model.predict(img, verbose=0)

predicted_index = int(np.argmax(pred))
confidence = float(np.max(pred)) * 100
predicted_class = class_names[predicted_index]

# Déterminer si sain ou malade
is_healthy = "healthy" in predicted_class.lower()
status = "✅ SAINE" if is_healthy else "🔴 MALADE"

# ─────────────────────────────────────────────
# RÉSULTATS
# ─────────────────────────────────────────────
print("\n" + "="*50)
print(f"  Résultat : {status}")
print(f"  Classe   : {predicted_class}")
print(f"  Fiabilité: {confidence:.2f}%")
print("="*50)

# Top-3 des probabilités
print("\n📊 Top 3 des probabilités :")
top3_indices = np.argsort(pred[0])[::-1][:3]
for i, idx in enumerate(top3_indices):
    cls = class_names[idx] if idx < len(class_names) else f"Classe_{idx}"
    prob = float(pred[0][idx]) * 100
    bar = "█" * int(prob / 5)
    print(f"  {i+1}. {cls:<35} {prob:5.2f}% {bar}")

print()