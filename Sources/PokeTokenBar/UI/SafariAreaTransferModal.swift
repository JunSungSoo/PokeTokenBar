import SwiftUI

@MainActor
struct SafariAreaTransferModal: View {
    let destination: SafariArea
    let language: AppLanguage
    let confirm: () -> Void
    private var l:L { L(language) }
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing:16) {
                Text(l.safariTravelTitle).font(.headline)
                Text(l.safariTravelMessage(destination)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                SafariFinishButton(title:l.battleConfirm,enabled:true,identifier:"safari-travel-confirm",action:confirm)
                    .fixedSize()
            }
            .padding(24).frame(width:360)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
            .shadow(radius:16)
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("safari-area-transfer")
        }
    }
}
