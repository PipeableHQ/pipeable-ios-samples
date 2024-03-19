import SwiftUI

struct ContentView: View {
    @State var showWeb = false
    @State var prompt: String = ""
    @State var showSuccess = false
    @State var showFailure = false
    
    var body: some View {
        ZStack {
            MainScreen(onButtonTapped: { newPrompt in
                prompt = newPrompt
                showWeb = true
                print("button feedback with prompt \(newPrompt)")
            })
            .sheet(isPresented: $showWeb) {
                AirBnBAgentWebView(
                    prompt: $prompt,
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
    @State private var inputText: String = "Please book me an Airbnb. I am going to Seoul, South Korea between Mar 25 and Mar 29. I am traveling with my wife. We want to rent an entire home and our budget is $100-150 per night. We prefer to stay at highly rated houses that have an instant booking option."
    @FocusState private var isTextEditorFocused: Bool
    
    var onButtonTapped: (_ prompt: String) -> Void
    
    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Spacer()
                    Text("Pipeable AirBnB Demo")
                        .bold()
                        .font(.title.width(.expanded))
                    
                    Spacer()
                }
            }
            
            HStack(alignment: .center) {
                Text(
                    """
                    Welcome to the Pipeable AirBnB Demo. Pipeable is an open-source iOS and (soon) Android SDK that allows developers to programmatically control webviews in mobile apps. Here we demonstrate how to build a simple AirBnB booking assistant.
                    """
                ).frame(maxWidth: .infinity)
                    .font(.callout).padding(.all, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(15)
                    .padding(.all, 10)
            }
            
            Spacer().frame(height: 10)

            HStack(alignment: .center) {
                Text(
                    """
                    I am an AirBnB booking assistant, you can give me information about your trip and I will help you book your room. I am a simple assistant so I can only help you pick the location, the number of guests, and some basic filters.
                    """
                ).frame(maxWidth: .infinity)
                    .font(.callout).padding(.all, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(15)
                    .padding(.all, 10)
            }
            
            Text("""
                 **Tell me about your trip**
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
            
            TextEditor(text: $inputText)
                .frame(minHeight: 100) // Adjust the height as needed
                .border(Color.gray, width: 1) // Optional: add a border to clearly define the text area
                .focused($isTextEditorFocused)
                  .padding()
                  .toolbar {
                      ToolbarItemGroup(placement: .keyboard) {
                          Spacer() // This spacer pushes the button to the trailing edge of the screen
                          
                          Button("Done") {
                              // Dismiss the keyboard
                              isTextEditorFocused = false
                          }
                      }
                  }
            
            Spacer()

            Button("Book") {
                onButtonTapped(inputText)
            }
            .frame(width: 150)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            
            Spacer()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
