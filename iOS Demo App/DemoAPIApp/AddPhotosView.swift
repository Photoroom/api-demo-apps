//
//  ContentView.swift
//  DemoAPIApp
//
//  Created by Vincent on 09/03/2023.
//

import SwiftUI

struct AddPhotosView: View {
    @State var showPicker = false
    @State var newPhoto: UIImage?
    @State var photos: [UIImage] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add photos")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Adding photos helps buyers understand what you are selling.")
                        .font(.callout)
                }

                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 0)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    AddPhotosButton {
                        showPicker = true
                    }

                    ForEach(0 ..< 9) { i in
                        PhotoButton(photoNumber: i + 1, photo: photos[safe: i]) {
                            showPicker = true
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            ZStack {
                Button {

                } label: {
                    Text("Save")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                }
            }
            .frame(height: 100)
            .background(
                Color.white
                    .edgesIgnoringSafeArea(.bottom)
                    .shadow(radius: 5)
            )
        }
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $newPhoto)
        }
        .onChange(of: newPhoto) { newPhoto in
            if let newPhoto {
                photos.append(newPhoto)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AddPhotosView()
        }
    }
}
