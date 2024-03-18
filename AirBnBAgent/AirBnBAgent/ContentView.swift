import SwiftUI


struct ContentView: View {
    @State var showWeb = false
    @State var showSuccess = false
    @State var showFailure = false
    @State var centralIndex = 0
    
    var body: some View {
        ZStack {
            MainScreen(onButtonTapped: {
                showWeb = true
            })
            .sheet(isPresented: $showWeb) {
                Pipeable_WebView(
                    onClose: {
                        showWeb = false
                    }, onResult: { status in
//                        showWeb = false
                        if status == .success {
                            showSuccess = true
                        } else if status == .failure {
                            showFailure = true
                        }
                    }
                )
            }
            
//            if showSuccess {
//                VStack {
//                    ToastView(header: "Success", text: "Card successfully set as default!", positive: true, isPresented: $showSuccess)
//                        .padding(.top, 20)
//                }
//            }
//            
            if showFailure {
                VStack {
                    ToastView(header: "Not supported", text: "Current operation is not supported!", positive: false, isPresented: $showFailure)
                        .padding(.top, 20)
                }
            }
        }
    }
}

struct MainScreen: View {
    @Environment(\.colorScheme) var colorScheme

    var onButtonTapped: () -> Void
    
    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Spacer()
                    Text("Pipeable Demo")
                        .bold()
                        .font(.title.width(.expanded))
                    
                    Spacer()
                }
            }
            
            HStack(alignment: .center) {
                Text("Welcome to the Pipeable demo app. Pipeable is a mobile webview automation SDK."
                ).frame(maxWidth: /*@START_MENU_TOKEN@*/ .infinity/*@END_MENU_TOKEN@*/)
                    .font(.title3).padding(.all, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(15)
                    .padding(.all, 10)
            }
            
            Spacer().frame(height: 10)
            
            Text("AirBnB Booking Agent").font(.title2).bold()
            
            Text("""
                 **Task**: Book a place in Seoul for 2 adults on March 20th to March 22nd, 2024 and enable instant book for a place that costs between $100 and $150 per night, and book the entire place.
                """
            ).frame(maxWidth: /*@START_MENU_TOKEN@*/ .infinity/*@END_MENU_TOKEN@*/)
                .font(.callout).padding(.all, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary, lineWidth: 2)
                )
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(10)
                .padding(.all, 10)
            
            Text("""
                **Plan**:
                1. Log into AirBnB
                2. Search for Seoul, South Korea
                3. Pick date range 03/20/2024 - 03/24/2024
                4. Select filters:
                    - price range: $100 - $150
                    - instant book: true
                5. Search
                6. Present results to user
                """
            ).frame(maxWidth: /*@START_MENU_TOKEN@*/ .infinity/*@END_MENU_TOKEN@*/)
                .font(.callout).padding(.all, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary, lineWidth: 2)
                )
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(10)
                .padding(.all, 10)
            

            Spacer()

            Button("Start") {
                onButtonTapped()
            }
            .frame(width: 150)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
//            Text("Note: You will be asked to log into the services. We never store any credentials or sensitive information on our servers.").italic().font(.system(size: 15))
            Spacer()
        }
//        .padding(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
