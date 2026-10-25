import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Unified Auth View (Slider as TabView, no redirect)
public struct WelcomeView: View {
    @Binding var showLogin: Bool
    @Binding var showCreate: Bool
    @Binding var isGuest: Bool
    @State private var selectedMode: AuthMode = .signIn
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.92

    public enum AuthMode: String, CaseIterable, Hashable {
        case signIn = "Sign In"
        case createAccount = "Create Account"

        /// Localized label rendered by the sign-in / create-account switch.
        var title: String {
            switch self {
            case .signIn: return L("Sign In")
            case .createAccount: return L("Create Account")
            }
        }
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle grid backdrop — very faint
            GeometryReader { geo in
                Canvas { context, size in
                    let lineColor = Color.white.opacity(0.035)
                    let spacing: CGFloat = 36
                    var x: CGFloat = 0
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(lineColor), lineWidth: 0.6)
                        x += spacing
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(lineColor), lineWidth: 0.6)
                        y += spacing
                    }
                }
                .ignoresSafeArea()
            }

            // Whole section centered middle — logo very big, no huge gaps, no padding between slide and username
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            // Logo placeholder dark — very big
                            LogoPlaceholderDarkView(height: 220)
                                .scaleEffect(logoScale)
                                .opacity(logoOpacity)
                                .padding(.bottom, 22)
                                .onAppear {
                                    withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                                        logoOpacity = 1
                                        logoScale = 1.0
                                    }
                                }

                            // Native TabView pill liquid glass — slider, close to login
                            AuthModeSlider(selectedMode: $selectedMode)
                                .padding(.horizontal, 16)

                            // Native TabView — swipeable, selection bound to slider, no gap to fields
                            TabView(selection: $selectedMode) {
                                SignInTab(isGuest: $isGuest, showLogin: $showLogin, showCreate: $showCreate)
                                    .tag(AuthMode.signIn)
                                CreateAccountTab(showLogin: $showLogin, showCreate: $showCreate)
                                    .tag(AuthMode.createAccount)
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(height: 268)
                            .animation(.spring(response: 0.42, dampingFraction: 0.68), value: selectedMode)
                        }
                        .padding(.vertical, 8)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: proxy.size.height)
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

// MARK: - Logo Placeholder Dark (replaces icon and name) — way bigger
private struct LogoPlaceholderDarkView: View {
    var height: CGFloat = 140
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let ui = UIImage(named: "ResilixLogoPlaceholderDark") ?? UIImage(named: "ResilixLogoPlaceholder") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                // Fallback if asset missing — keep dark style
                VStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(.white)
                    Text(L("RESILIX"))
                        .font(.system(size: 28, weight: .heavy, design: .default))
                        .tracking(3)
                        .foregroundStyle(.white)
                    Text(L("CONNECT WITHOUT THE INTERNET"))
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .tracking(1.4)
                        .foregroundStyle(ResilixTheme.brandCyan)
                }
            }
            #else
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 54))
                .foregroundStyle(.white)
            #endif
        }
        .frame(maxWidth: .infinity)
        accessibilityLabel(Text(L("Resilix logo")))
    }
}

// MARK: - Slider pill liquid glass — holdable & movable like TabView
private struct AuthModeSlider: View {
    @Binding var selectedMode: WelcomeView.AuthMode
    @Namespace private var pill

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(WelcomeView.AuthMode.allCases, id: \.self) { mode in
                    Text(mode.title)
                        .font(ResilixTheme.font(14, .semibold))
                        .tracking(0.2)
                        .foregroundStyle(selectedMode == mode ? Color.black : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Capsule())
                        .background {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(ResilixTheme.brandCyan)
                                    .liquidGlassCapsule(interactive: true)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.68, blendDuration: 0.2)) {
                                selectedMode = mode
                            }
                        }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            )
            .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.68, blendDuration: 0.2), value: selectedMode)
            .contentShape(Capsule())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let target: WelcomeView.AuthMode = value.location.x < (w / 2) ? .signIn : .createAccount
                        if target != selectedMode {
                            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.68, blendDuration: 0.2)) {
                                selectedMode = target
                            }
                        }
                    }
            )
        }
        .frame(height: 44)
    }
}

// MARK: - Sign In Tab (exactly like first image) — liquid glass
private struct SignInTab: View {
    @Binding var isGuest: Bool
    @Binding var showLogin: Bool
    @Binding var showCreate: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showPassword = false

    var body: some View {
        VStack(spacing: 12) {
            AuthInputField(
                placeholder: L("Email or username"),
                text: $email,
                icon: "person",
                keyboardType: .emailAddress,
                contentType: .username
            )

            AuthSecureField(
                placeholder: L("Password"),
                text: $password,
                showPassword: $showPassword
            )

            if let e = error {
                Text(e)
                    .font(ResilixTheme.font(12, .regular))
                    .foregroundStyle(ResilixTheme.emergencyRed.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                guard !email.trimmingCharacters(in: .whitespaces).isEmpty,
                      !password.isEmpty else {
                    error = L("Enter email and password.")
                    return
                }
                error = nil
                loading = true
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        loading = false
                        showLogin = true
                        NotificationCenter.default.post(name: .authSuccess, object: nil)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if loading { ProgressView().tint(Color.black) }
                    Text(L("SIGN IN"))
                        .font(ResilixTheme.font(15, .heavy))
                        .tracking(0.8)
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(ResilixTheme.brandCyan)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .blendMode(.overlay)
                )
                .liquidGlassRounded(cornerRadius: 18, interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .disabled(loading)

            Button {
                isGuest = true
            } label: {
                Text(L("Continue as Guest"))
                    .font(ResilixTheme.font(14, .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.top, 4)
            accessibilityLabel(Text(L("Continue as guest")))
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
    }
}

// MARK: - Create Account Tab (exactly like second image) — liquid glass
private struct CreateAccountTab: View {
    @Binding var showLogin: Bool
    @Binding var showCreate: Bool
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            AuthInputField(
                placeholder: L("Choose a username"),
                text: $username,
                icon: "person",
                keyboardType: .default
            )

            AuthSecureField(
                placeholder: L("Password"),
                text: $password,
                showPassword: $showPassword
            )

            if let e = error {
                Text(e)
                    .font(ResilixTheme.font(12, .regular))
                    .foregroundStyle(ResilixTheme.emergencyRed.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                guard !username.trimmingCharacters(in: .whitespaces).isEmpty,
                      !password.isEmpty else {
                    error = L("Fill in all fields.")
                    return
                }
                error = nil
                loading = true
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        loading = false
                        showCreate = true
                        NotificationCenter.default.post(name: .authSuccess, object: nil)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if loading { ProgressView().tint(Color.black) }
                    Text(L("CREATE ACCOUNT"))
                        .font(ResilixTheme.font(15, .heavy))
                        .tracking(0.8)
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(ResilixTheme.brandCyan)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .blendMode(.overlay)
                )
                .liquidGlassRounded(cornerRadius: 18, interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .disabled(loading || username.isEmpty || password.isEmpty)
            .opacity(username.isEmpty || password.isEmpty ? 0.9 : 1)

            Button {
                NotificationCenter.default.post(name: .authSuccess, object: nil)
            } label: {
                Text(L("Continue as Guest"))
                    .font(ResilixTheme.font(14, .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
    }
}

// MARK: - Auth Input Fields — liquid glass native + liquid glass borders
private struct AuthInputField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var contentType: UITextContentType? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
                .font(ResilixTheme.font(15, .regular))
                .tint(ResilixTheme.brandCyan)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder)
                        .font(ResilixTheme.font(15, .regular))
                        .foregroundStyle(Color.white.opacity(0.32))
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .liquidGlassRounded(cornerRadius: 18, interactive: false)
    }
}

private struct AuthSecureField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 20)

            Group {
                if showPassword {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .foregroundStyle(.white)
            .font(ResilixTheme.font(15, .regular))
            .tint(ResilixTheme.brandCyan)
            .placeholder(when: text.isEmpty) {
                Text(placeholder)
                    .font(ResilixTheme.font(15, .regular))
                    .foregroundStyle(Color.white.opacity(0.32))
            }

            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .liquidGlassRounded(cornerRadius: 18, interactive: false)
    }
}

// Placeholder modifier helper
private extension View {
    func placeholder<Content: View>(when shouldShow: Bool, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Auth success notification
extension Notification.Name {
    static let authSuccess = Notification.Name("authSuccess")
}

// MARK: - Legacy Login / Create views kept for navigation compatibility (now wrappers) — also dark placeholder + liquid glass

public struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    var onSuccess: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var loading = false
    @State private var error: String?

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        LogoPlaceholderDarkView().padding(.top, 40)
                        VStack(spacing: 12) {
                            AuthInputField(placeholder: L("Email or username"), text: $email, icon: "person")
                            AuthSecureField(placeholder: L("Password"), text: $password, showPassword: $showPassword)
                            if let e = error {
                                Text(e).font(ResilixTheme.font(12, .regular)).foregroundStyle(ResilixTheme.emergencyRed).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button {
                                guard !email.isEmpty, !password.isEmpty else { error = L("Enter email and password."); return }
                                loading = true
                                Task { try? await Task.sleep(nanoseconds: 500_000_000); await MainActor.run { loading = false; onSuccess() } }
                            } label: {
                                HStack { if loading { ProgressView().tint(Color.black) }; Text(L("SIGN IN")).font(ResilixTheme.font(15, .heavy)).tracking(0.8) }
                                    .foregroundStyle(Color.black).frame(maxWidth: .infinity).frame(height: 56)
                                    .background(ResilixTheme.brandCyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .liquidGlassRounded(cornerRadius: 18, interactive: true)
                            }
                            .buttonStyle(.plain)
                            Button(L("Continue as Guest")) { onSuccess() }.font(ResilixTheme.font(14, .semibold)).foregroundStyle(Color.white.opacity(0.55))
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 24)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { dismiss() }.foregroundStyle(Color.white.opacity(0.7)) } }
        }
    }
    public init(onSuccess: @escaping () -> Void) { self.onSuccess = onSuccess }
}

public struct CreateAccountView: View {
    @Environment(\.dismiss) var dismiss
    var onSuccess: () -> Void
    @State private var name = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var loading = false

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        LogoPlaceholderDarkView().padding(.top, 40)
                        VStack(spacing: 12) {
                            AuthInputField(placeholder: L("Choose a username"), text: $name, icon: "person")
                            AuthSecureField(placeholder: L("Password"), text: $password, showPassword: $showPassword)
                            Button {
                                loading = true
                                Task { try? await Task.sleep(nanoseconds: 500_000_000); await MainActor.run { loading = false; onSuccess() } }
                            } label: {
                                Text(L("CREATE ACCOUNT")).font(ResilixTheme.font(15, .heavy)).tracking(0.8).foregroundStyle(Color.black).frame(maxWidth: .infinity).frame(height: 56)
                                    .background(ResilixTheme.brandCyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).liquidGlassRounded(cornerRadius: 18, interactive: true)
                            }
                            .buttonStyle(.plain).disabled(name.isEmpty || password.isEmpty).opacity(name.isEmpty || password.isEmpty ? 0.9 : 1)
                        }.padding(.horizontal, 24)
                    }.padding(.bottom, 24)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { dismiss() }.foregroundStyle(Color.white.opacity(0.7)) } }
        }
    }
    public init(onSuccess: @escaping () -> Void) { self.onSuccess = onSuccess }
}

// MARK: - Legacy custom fields kept for compatibility (wrap new liquid glass fields)
struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var contentType: UITextContentType?
    var body: some View {
        AuthInputField(placeholder: placeholder, text: $text, icon: icon, keyboardType: keyboardType, contentType: contentType)
    }
}
struct CustomSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    @State private var showPassword = false
    var body: some View {
        AuthSecureField(placeholder: placeholder, text: $text, showPassword: $showPassword)
    }
}

#Preview {
    WelcomeView(showLogin: .constant(false), showCreate: .constant(false), isGuest: .constant(false))
        .environmentObject(ResilixAppModel())
}
