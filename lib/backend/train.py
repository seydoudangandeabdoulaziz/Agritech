import tensorflow as tf
from tensorflow.keras.preprocessing.image import ImageDataGenerator
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.models import Model
from tensorflow.keras.layers import Dense, GlobalAveragePooling2D, Dropout
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint, ReduceLROnPlateau
import os

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
dataset_type = "color"
train_dir   = f"./dataset/{dataset_type}/train"
test_dir    = f"./dataset/{dataset_type}/test"
model_dir   = "./models"
os.makedirs(model_dir, exist_ok=True)

img_size   = (224, 224)
batch_size = 32
epochs     = 20  # Plus d'époques, EarlyStopping arrêtera au bon moment

# ─────────────────────────────────────────────
# 1. GÉNÉRATEURS D'IMAGES
# ─────────────────────────────────────────────
train_datagen = ImageDataGenerator(
    rescale=1./255,
    rotation_range=20,
    width_shift_range=0.2,
    height_shift_range=0.2,
    horizontal_flip=True,
    zoom_range=0.15,          # ✅ AJOUT : zoom aléatoire
    brightness_range=[0.8, 1.2],  # ✅ AJOUT : variation de luminosité
    validation_split=0.2
)

test_datagen = ImageDataGenerator(rescale=1./255)

train_generator = train_datagen.flow_from_directory(
    train_dir, target_size=img_size, batch_size=batch_size,
    class_mode="categorical", subset="training",
    shuffle=True
)

val_generator = train_datagen.flow_from_directory(
    train_dir, target_size=img_size, batch_size=batch_size,
    class_mode="categorical", subset="validation",
    shuffle=False
)

# ✅ CORRECTION : Utilisation du dataset de test
test_generator = test_datagen.flow_from_directory(
    test_dir, target_size=img_size, batch_size=batch_size,
    class_mode="categorical", shuffle=False
)

num_classes = len(train_generator.class_indices)
print(f"✅ {num_classes} classes détectées : {list(train_generator.class_indices.keys())}")

# ✅ CORRECTION 1 : Sauvegarde immédiate des classes dans un fichier texte
classes_file = f"{model_dir}/classes_{dataset_type}.txt"
with open(classes_file, "w") as f:
    for cls, idx in sorted(train_generator.class_indices.items(), key=lambda x: x[1]):
        f.write(cls + "\n")
print(f"✅ Classes sauvegardées dans {classes_file}")

# ─────────────────────────────────────────────
# 2. CONSTRUCTION DU MODÈLE
# ─────────────────────────────────────────────
base_model = MobileNetV2(input_shape=(224, 224, 3), include_top=False, weights="imagenet")

# Phase 1 : Entraîner uniquement les couches ajoutées
base_model.trainable = False

x = base_model.output
x = GlobalAveragePooling2D()(x)
x = Dense(256, activation="relu")(x)   # ✅ AJOUT : couche plus large
x = Dropout(0.4)(x)
x = Dense(128, activation="relu")(x)
x = Dropout(0.3)(x)
output_layer = Dense(num_classes, activation="softmax")(x)

model = Model(inputs=base_model.input, outputs=output_layer)

# ─────────────────────────────────────────────
# 3. CALLBACKS
# ─────────────────────────────────────────────
callbacks = [
    # ✅ AJOUT : Arrêt si la val_loss ne s'améliore plus pendant 5 époques
    EarlyStopping(
        monitor="val_loss",
        patience=5,
        restore_best_weights=True,
        verbose=1
    ),
    # ✅ AJOUT : Sauvegarde uniquement du meilleur modèle
    ModelCheckpoint(
        filepath=f"{model_dir}/mobilenetv2_{dataset_type}_best.h5",
        monitor="val_accuracy",
        save_best_only=True,
        verbose=1
    ),
    # ✅ AJOUT : Réduction du learning rate si stagnation
    ReduceLROnPlateau(
        monitor="val_loss",
        factor=0.5,
        patience=3,
        min_lr=1e-7,
        verbose=1
    ),
]

# ─────────────────────────────────────────────
# 4. PHASE 1 : ENTRAÎNEMENT DES COUCHES AJOUTÉES
# ─────────────────────────────────────────────
print("\n🚀 Phase 1 : Entraînement des couches de classification...")
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.0001),
    loss="categorical_crossentropy",
    metrics=["accuracy"]
)

model.fit(
    train_generator,
    validation_data=val_generator,
    epochs=epochs,
    callbacks=callbacks
)

# ─────────────────────────────────────────────
# 5. PHASE 2 : FINE-TUNING (débloquer les dernières couches)
# ─────────────────────────────────────────────
print("\n🔧 Phase 2 : Fine-tuning des dernières couches de MobileNetV2...")

# ✅ CORRECTION 2 : Débloquer les 30 dernières couches de MobileNetV2
base_model.trainable = True
for layer in base_model.layers[:-30]:
    layer.trainable = False

# Learning rate plus faible pour le fine-tuning
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.00001),
    loss="categorical_crossentropy",
    metrics=["accuracy"]
)

model.fit(
    train_generator,
    validation_data=val_generator,
    epochs=10,
    callbacks=callbacks
)

# ─────────────────────────────────────────────
# 6. ÉVALUATION SUR LE DATASET DE TEST
# ─────────────────────────────────────────────
print("\n📊 Évaluation sur le dataset de test...")
# ✅ CORRECTION 3 : Évaluation sur test_generator
test_loss, test_accuracy = model.evaluate(test_generator, verbose=1)
print(f"\n✅ Accuracy sur le test  : {test_accuracy * 100:.2f}%")
print(f"✅ Loss sur le test      : {test_loss:.4f}")

# ─────────────────────────────────────────────
# 7. SAUVEGARDE FINALE
# ─────────────────────────────────────────────
final_model_path = f"{model_dir}/mobilenetv2_{dataset_type}.h5"
model.save(final_model_path)
print(f"\n✅ Modèle final sauvegardé : {final_model_path}")
print(f"✅ Meilleur modèle sauvegardé : {model_dir}/mobilenetv2_{dataset_type}_best.h5")
print(f"✅ Classes sauvegardées : {classes_file}")