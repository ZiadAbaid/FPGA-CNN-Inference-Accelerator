import tensorflow as tf
from tensorflow.keras import layers, models

# ─────────────────────────────────────────────
#  3-CLASS MODEL TRAINER: Cat / Dog / Human
# ─────────────────────────────────────────────

print("Loading images from Doglets/...")
dataset = tf.keras.utils.image_dataset_from_directory(
    "Doglets",
    color_mode="grayscale",
    image_size=(32, 32),
    batch_size=32,
    shuffle=True,
    seed=42
)

class_names = dataset.class_names
print(f"Class mapping: {list(enumerate(class_names))}")

# Split off 20% for validation
total_batches = tf.data.experimental.cardinality(dataset).numpy()
val_size   = int(total_batches * 0.2)
train_size = total_batches - val_size

train_ds = dataset.take(train_size).cache().prefetch(tf.data.AUTOTUNE)
val_ds   = dataset.skip(train_size).cache().prefetch(tf.data.AUTOTUNE)

# ─────────────────────────────────────────────
#  Build the brain (Updated with Normalization)
# ─────────────────────────────────────────────
model = models.Sequential([
    layers.Input(shape=(32, 32, 1)),
    layers.Rescaling(1./255), # Normalizes 0-255 pixels to 0.0-1.0
    
    layers.Conv2D(16, (3, 3), activation='relu', padding='same'),
    layers.MaxPooling2D((2, 2)),
    
    layers.Conv2D(32, (3, 3), activation='relu', padding='same'),
    layers.MaxPooling2D((2, 2)),
    
    layers.Conv2D(32, (3, 3), activation='relu', padding='same'),
    layers.MaxPooling2D((2, 2)),
    
    layers.Flatten(),
    layers.Dense(32, activation='relu'),
    layers.Dense(3, activation='softmax')
])

model.compile(
    optimizer='adam',
    loss='sparse_categorical_crossentropy',
    metrics=['accuracy']
)

# ─────────────────────────────────────────────
#  Train (Increased to 30 Epochs for convergence)
# ─────────────────────────────────────────────
print("\nStarting training (30 epochs)...")
model.fit(train_ds, validation_data=val_ds, epochs=50)

model.save("tiny_ai_brain.h5")
print("\nTraining complete! Saved as tiny_ai_brain.h5")