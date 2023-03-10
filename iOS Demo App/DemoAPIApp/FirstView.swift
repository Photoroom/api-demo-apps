//
//  FirstView.swift
//  DemoAPIApp
//
//  Created by Vincent on 10/03/2023.
//

import SwiftUI

struct FirstView: View {
    var body: some View {
        NavigationLink("Go to Add Photos") {
            AddPhotosView()
        }
        .navigationTitle("")
    }
}

struct FirstView_Previews: PreviewProvider {
    static var previews: some View {
        FirstView()
    }
}
