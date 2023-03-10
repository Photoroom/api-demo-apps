//
//  AddPhotosButton.swift
//  DemoAPIApp
//
//  Created by Vincent on 09/03/2023.
//

import SwiftUI

struct AddPhotosButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void = {}) {
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                ZStack(alignment: .topLeading) {
                    Image(systemName: "camera")
                    Image(systemName: "plus.circle.fill")
                        .background(Color.white)
                        .clipShape(Circle())
                        .font(.system(size: 16))
                }
                    .font(.largeTitle)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .center
                    )
                Text("Add up to 10 photos")
                    .font(.system(size: 18))
                    .fontWeight(.semibold)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
            }
            .fontWeight(.semibold)
            .padding(8)
            .aspectRatio(1.0, contentMode: .fit)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AddPhotosButton_Previews: PreviewProvider {
    static var previews: some View {
        AddPhotosButton()
            .frame(width: 160, height: 160)
    }
}
