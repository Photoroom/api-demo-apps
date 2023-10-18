# PhotoRoom API Web Demo app

This project shows a simple example of how the PhotoRoom API can be integrated in a simple webapp.

You can try it [here](https://photoroom-api-web-demo.vercel.app)! (please note that you will need to [get your `apiKey`](https://app.photoroom.com/api-dashboard))

## How to add your own branding?

It should be pretty easy to customize the selfie generator with your own branding:

* the directory `assets` contains the background and overlay images
* the font of the text is loaded in `index.html` using Google Fonts
* the color and font of the text are defined in `script.js`, in the function `drawImageWithOverlay()`
