//
//  MissingPhotoButton.swift
//  DemoAPIApp
//
//  Created by Vincent on 09/03/2023.
//

import SwiftUI

struct PhotoButton: View {
    let photoNumber: Int
    let photo: UIImage?
    let action: () -> Void

    init(
        photoNumber: Int,
        photo: UIImage?,
        action: @escaping () -> Void = {}
    ) {
        self.photoNumber = photoNumber
        self.photo = photo
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Image(systemName: "photo.fill")
                    .font(.largeTitle)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .center
                    )
                Text("Photo \(photoNumber)")
                    .font(.system(size: 18))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
            }
            .fontWeight(.semibold)
            .padding()
            .aspectRatio(1.0, contentMode: .fit)
            .background(Color.white)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            style: StrokeStyle(lineWidth: 2, dash: [5])
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.gray)
        }
    }
}

struct PhotoButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PhotoButton(photoNumber: 1, photo: nil)
            PhotoButton(photoNumber: 2, photo: UIImage(named: "photo"))
        }
        .frame(width: 160, height: 160)
    }
}
