import Foundation
import SwiftUI

struct ToastView: View {
    var header: String
    var text: String
    var positive: Bool
    
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Image(systemName: "info.circle.fill")
                    .resizable()
                    .foregroundColor(positive ? Color.green : Color.red)
                    .frame(width: 25, height: 25)
                    .padding(.trailing, 10)
                
                VStack(alignment: .leading) {
                    Text(header)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.bottom, 5)
                    
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(Color.primary.opacity(0.8))
                        
                }
                
                Spacer(minLength: 10)
                
                Button {
                    isPresented.toggle()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(Color.primary)
                }
            }
            .padding()
            .padding(.vertical, 5)
        }
        .background(Color(.darkGray))
        .overlay(
            Rectangle()
                .fill(positive ? Color.green : Color.red)
                .frame(width: 6)
                .clipped()
            , alignment: .leading
        )
        .frame(minWidth: 0, maxWidth: .infinity)
        .cornerRadius(8)
        .shadow(color: Color.primary.opacity(0.25), radius: 4, x: 5, y: 5)
        .padding(.horizontal, 16)
    }
}


struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        @State var isPresented = true
        
        VStack {
            ToastView(header: "Success", text: "Operation successful!", positive: true, isPresented: $isPresented)
        }
    }
}
