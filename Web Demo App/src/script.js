// script.js
const apiKeyInput = document.getElementById("api-key")
const uploadForm = document.getElementById("upload-form")
const imageInput = document.getElementById("image-input")
const overlayText = document.getElementById("overlay-text")
const resultContainer = document.getElementById("result-container")
const resultCanvas = document.getElementById("result-canvas")
const scaleRange = document.getElementById("scale-range")
const rotationRange = document.getElementById("rotation-range")
const moveUpButton = document.getElementById("arrow-up")
const moveDownButton = document.getElementById("arrow-down")
const moveLeftButton = document.getElementById("arrow-left")
const moveRightButton = document.getElementById("arrow-right")

let apiKey
let segmentedPhoto
let scaleFactor = 1
let rotationDegrees = 0

const moveStep = 10 // Change this value to adjust the step size when moving the image
let userOffsetX = 0
let userOffsetY = 0

uploadForm.addEventListener("submit", async (event) => {
    event.preventDefault()
    if (!imageInput.files[0]) return

    const image = await loadImage(imageInput.files[0])
    segmentedPhoto = await removeBackground(image)
    updateImage()
})

apiKeyInput.addEventListener("input", (event) => {
    apiKey = event.target.value
})

overlayText.addEventListener("input", () => {
    updateImage()
})

scaleRange.addEventListener("input", (event) => {
    scaleFactor = parseFloat(event.target.value)
    updateImage()
})

rotationRange.addEventListener("input", (event) => {
    rotationDegrees = parseFloat(event.target.value)
    updateImage()
})

moveUpButton.addEventListener("click", () => {
    userOffsetY -= moveStep
    updateImage()
})

moveDownButton.addEventListener("click", () => {
    userOffsetY += moveStep
    updateImage()
})

moveLeftButton.addEventListener("click", () => {
    userOffsetX -= moveStep
    updateImage()
})

moveRightButton.addEventListener("click", () => {
    userOffsetX += moveStep
    updateImage()
})

async function updateImage() {
    if (!segmentedPhoto) return

    const text = overlayText.value

    const finalImage = await drawImageWithOverlay(segmentedPhoto, text, scaleFactor, rotationDegrees)

    resultContainer.style.display = "block"
    resultCanvas.width = finalImage.width
    resultCanvas.height = finalImage.height
    const ctx = resultCanvas.getContext("2d")
    ctx.drawImage(finalImage, 0, 0)

    // Update download button
    const downloadButton = document.getElementById("download-button")
    downloadButton.style.display = "block"
    finalImage.toBlob((blob) => {
        const url = URL.createObjectURL(blob)
        downloadButton.href = url
    })
}

async function loadImage(file) {
    return new Promise((resolve) => {
        const reader = new FileReader()
        reader.onload = (event) => {
            const image = new Image()
            image.src = event.target.result
            image.onload = () => resolve(image)
        }
        reader.readAsDataURL(file)
    })
}

function loadLocalImage(src) {
    return new Promise((resolve, reject) => {
        const img = new Image()
        img.src = src
        img.onload = () => resolve(img)
        img.onerror = (err) => reject(err)
    })
}

async function removeBackground() {
    const formData = new FormData()
    formData.append("image_file", imageInput.files[0])
    formData.append("format", "png")

    const response = await fetch("https://sdk.photoroom.com/v1/segment", {
        method: "POST",
        headers: {
            "X-Api-Key": apiKey,
        },
        body: formData,
    })

    if (!response.ok) throw new Error("Failed to remove background")

    const blob = await response.blob()
    return await loadImage(blob)
}

async function drawImageWithOverlay(image, text, scaleFactor = 1, rotation = 0) {
    const background = await loadLocalImage("background.png")
    const overlay = await loadLocalImage("overlay.png")

    const newHeight = 1920
    const newWidth = 1080

    const scale = Math.min(newWidth / image.width, newHeight / image.height)
    const scaledWidth = image.width * scale
    const scaledHeight = image.height * scale

    const canvas = document.createElement("canvas")
    canvas.width = newWidth
    canvas.height = newHeight
    const ctx = canvas.getContext("2d")

    // Draw sky background (replace with desired background)
    ctx.drawImage(background, 0, 0, newWidth, newHeight)

    // Calculate the new scaled width and height
    const newScaledWidth = scaledWidth * scaleFactor
    const newScaledHeight = scaledHeight * scaleFactor

    // Adjust offsetX and offsetY to keep the image centered
    const newOffsetX = (newWidth - newScaledWidth) / 2
    const newOffsetY = (newHeight - newScaledHeight) / 2

    // Draw the centered, scaled, and rotated image with the removed background
    ctx.save()
    ctx.translate(newWidth / 2, newHeight / 2) // Translate to the center of the canvas
    ctx.rotate(rotation * (Math.PI / 180)) // Convert degrees to radians and rotate the context
    ctx.translate(-newWidth / 2, -newHeight / 2) // Translate back to the origin
    ctx.drawImage(image, newOffsetX + userOffsetX, newOffsetY + userOffsetY, newScaledWidth, newScaledHeight)
    ctx.restore()
  
    // Draw overlay on top
    ctx.drawImage(overlay, 0, 0, newWidth, newHeight)

    // Add text overlay
    const fontSize = 58 // Increased font size
    const curveRadius = 400 // Adjusted curve radius for less curvature
    const centerX = newWidth / 2
    const centerY = newHeight / 2 - 300
    const whiteSpaceWidth = 15
    const lineHeight = 58

    ctx.font = `bold ${fontSize}px 'DM Sans', sans-serif`
    ctx.fillStyle = "#000000"

    const lines = ['This person is ', text]
    let cursorPositionY = 0

    for (const line of lines) {
        const lineWidth = ctx.measureText(line).width
        const words = line.split(" ")
        const totalAngle = lineWidth / curveRadius
        const startAngle = (-Math.PI - totalAngle) / 2
        const endAngle = startAngle + totalAngle

        let cursorPositionX = 0

        for (let i = 0; i < words.length; i++) {
            const word = words[i]

            for (let j = 0; j < word.length; j++) {
                const char = word.charAt(j)
                const charWidth = ctx.measureText(char).width

                const x = cursorPositionX / lineWidth
                const angle = startAngle + x * (endAngle  - startAngle)

                ctx.save()
                ctx.translate(
                    centerX + curveRadius * Math.cos(angle),
                    centerY + curveRadius * Math.sin(angle) + cursorPositionY
                    )
                ctx.rotate(Math.PI / 2 + angle)
                ctx.fillText(char, 0, 0)
                ctx.restore()

                cursorPositionX += charWidth
            }

            cursorPositionX += whiteSpaceWidth
        }

        cursorPositionY += lineHeight
    }

    return canvas
}

