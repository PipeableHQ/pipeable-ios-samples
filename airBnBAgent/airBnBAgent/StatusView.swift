import Foundation
import SwiftUI
import Combine


struct StatusView: View {
    var text: String
    var animated: Bool = false
    var done: Bool = false
    var userControl: Bool = false
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    @State private var numberOfDots: Int = 0
    
    var dots: String {
        String(repeating: ".", count: animated ? numberOfDots : 0)
    }
    
    var body: some View {
        ZStack {
            // Invisible overlay to capture all taps when modal is visible
            Color.clear
                .contentShape(Rectangle()) // Make entire area tappable
                .onTapGesture {
                    // Handle or ignore tap gesture
                }
                .edgesIgnoringSafeArea(.all)
            
            
            // Modal content
            
            VStack {
                
                VStack {
                    VStack {
                        VStack {
                            ZStack {
                                HStack {
                                    Text(text + dots)
                                        .foregroundColor(Color.primary)
                                        .font(.title3)
                                        .transition(.opacity)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
//                        .frame(width: UIScreen.main.bounds.width - 40, height: 70)
                    }
                    .background(userControl ? Color(.systemBackground) : Color(.darkGray))
                    .cornerRadius(15)  // Optional rounding
                    .shadow(radius: 10) // Optional shadow
                    .transition(.move(edge: .bottom)) // Animation for modal appearance
                }
                .padding(.all, 20)
                
                Spacer()

            }
            .background(done ? Color.gray.opacity(0.7) : Color.gray.opacity(0.0))
//            .edgesIgnoringSafeArea(.all)
        }
        .onReceive(timer) { _ in
            if animated {
                numberOfDots = (numberOfDots + 1) % 4
            }
        }
        .onDisappear() {
            timer.upstream.connect().cancel()
        }
    }
}


struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
//            StatusView(text: "👤  Please log into your account")
            StatusView(text: "🤖  Robot working, please wait", animated: true)
//            StatusView(text: "✅  Card successfully set as default")
        }
    }
}
