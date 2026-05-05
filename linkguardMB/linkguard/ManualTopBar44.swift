import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
private struct ManualTopBarUIView: UIViewRepresentable {
    let title: String
    let backTitle: String
    let trailingText: String?
    let trailingSystemImage: String?
    let onBack: () -> Void
    let onTrailingTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onBack: onBack, onTrailingTap: onTrailingTap)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBackground

        let backButton = UIButton(type: .system)
        var backConfig = UIButton.Configuration.plain()
        backConfig.image = UIImage(systemName: "chevron.left")
        backConfig.title = backTitle
        backConfig.imagePadding = 4
        backConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = backConfig
        backButton.setContentHuggingPriority(.required, for: .horizontal)
        backButton.addTarget(context.coordinator, action: #selector(Coordinator.didTapBack), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let trailingLabel = UILabel()
        trailingLabel.textAlignment = .right
        trailingLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        trailingLabel.textColor = UIColor.secondaryLabel
        trailingLabel.isHidden = true

        let trailingButton = UIButton(type: .system)
        trailingButton.isHidden = true
        trailingButton.setContentHuggingPriority(.required, for: .horizontal)
        trailingButton.addTarget(context.coordinator, action: #selector(Coordinator.didTapTrailing), for: .touchUpInside)

        let separator = UIView()
        separator.backgroundColor = UIColor.separator

        [backButton, titleLabel, trailingLabel, trailingButton, separator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            trailingButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            trailingButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            trailingLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            trailingLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButton.leadingAnchor, constant: -8),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        context.coordinator.backButton = backButton
        context.coordinator.titleLabel = titleLabel
        context.coordinator.trailingLabel = trailingLabel
        context.coordinator.trailingButton = trailingButton
        context.coordinator.apply(
            title: title,
            backTitle: backTitle,
            trailingText: trailingText,
            trailingSystemImage: trailingSystemImage,
            onTrailingTap: onTrailingTap
        )

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.apply(
            title: title,
            backTitle: backTitle,
            trailingText: trailingText,
            trailingSystemImage: trailingSystemImage,
            onTrailingTap: onTrailingTap
        )
    }

    final class Coordinator: NSObject {
        var onBack: () -> Void
        var onTrailingTap: (() -> Void)?

        weak var backButton: UIButton?
        weak var titleLabel: UILabel?
        weak var trailingLabel: UILabel?
        weak var trailingButton: UIButton?

        init(onBack: @escaping () -> Void, onTrailingTap: (() -> Void)?) {
            self.onBack = onBack
            self.onTrailingTap = onTrailingTap
        }

        func apply(
            title: String,
            backTitle: String,
            trailingText: String?,
            trailingSystemImage: String?,
            onTrailingTap: (() -> Void)?
        ) {
            self.onTrailingTap = onTrailingTap

            titleLabel?.text = title

            var backConfig = UIButton.Configuration.plain()
            backConfig.image = UIImage(systemName: "chevron.left")
            backConfig.title = backTitle
            backConfig.imagePadding = 4
            backConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            backButton?.configuration = backConfig

            if let trailingText {
                trailingLabel?.isHidden = false
                trailingLabel?.text = trailingText
                trailingButton?.isHidden = true
            } else if let trailingSystemImage, onTrailingTap != nil {
                var config = UIButton.Configuration.plain()
                config.image = UIImage(systemName: trailingSystemImage)
                config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                trailingButton?.configuration = config
                trailingButton?.isHidden = false
                trailingLabel?.isHidden = true
            } else {
                trailingLabel?.isHidden = true
                trailingButton?.isHidden = true
            }
        }

        @objc func didTapBack() {
            onBack()
        }

        @objc func didTapTrailing() {
            onTrailingTap?()
        }
    }
}

private struct ManualTopBar44Modifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let trailingText: String?
    let trailingSystemImage: String?
    let onTrailingTap: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ManualTopBarUIView(
                    title: title,
                    backTitle: L("返回"),
                    trailingText: trailingText,
                    trailingSystemImage: trailingSystemImage,
                    onBack: { dismiss() },
                    onTrailingTap: onTrailingTap
                )
                .frame(height: 44)
            }
    }
}

extension View {
    func manualTopBar44(
        title: String,
        trailingText: String? = nil,
        trailingSystemImage: String? = nil,
        onTrailingTap: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ManualTopBar44Modifier(
                title: title,
                trailingText: trailingText,
                trailingSystemImage: trailingSystemImage,
                onTrailingTap: onTrailingTap
            )
        )
    }
}
#else
extension View {
    func manualTopBar44(
        title: String,
        trailingText: String? = nil,
        trailingSystemImage: String? = nil,
        onTrailingTap: (() -> Void)? = nil
    ) -> some View {
        self
    }
}
#endif
