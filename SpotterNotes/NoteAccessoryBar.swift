import UIKit

/// The formatting row above the keyboard. Every control maps to one `NoteTouchCommand`; nothing here edits text itself.
final class NoteAccessoryBar: UIInputView {
    private let handler: (NoteTouchCommand) -> Void
    private let dismiss: () -> Void

    init(handler: @escaping (NoteTouchCommand) -> Void, dismiss: @escaping () -> Void) {
        self.handler = handler
        self.dismiss = dismiss
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: NotesTheme.Size.accessoryBar),
            inputViewStyle: .keyboard)
        autoresizingMask = .flexibleWidth

        let commands = UIStackView(arrangedSubviews: [
            button("Checklist", symbol: "checklist", command: .checklist),
            button("Bulleted List", symbol: "list.bullet", command: .block(.bulletedList)),
            button("Numbered List", symbol: "list.number", command: .block(.numberedList)),
            menuButton(
                "Paragraph Style", symbol: "textformat.size",
                items: [
                    ("Text", "text.alignleft", .block(.text)),
                    ("Heading 1", "1.square", .block(.heading1)),
                    ("Heading 2", "2.square", .block(.heading2)),
                    ("Heading 3", "3.square", .block(.heading3)),
                ]),
            menuButton("Format", symbol: "bold.italic.underline", items: Self.inlineItems),
            button("Decrease Indent", symbol: "decrease.indent", command: .indent(.outdent)),
            button("Increase Indent", symbol: "increase.indent", command: .indent(.indent)),
        ])
        // Scrolls rather than squeezes, so every control keeps a full touch target in a narrow split view.
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(commands)
        let done = UIButton(
            configuration: .plain(),
            primaryAction: UIAction(image: UIImage(systemName: "keyboard.chevron.compact.down")) {
                [dismiss] _ in dismiss()
            })
        done.accessibilityLabel = "Hide Keyboard"

        for view in [scroll, commands, done] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(scroll)
        addSubview(done)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor),
            done.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: NotesTheme.Size.accessoryButton),
            commands.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            commands.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            commands.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            commands.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            commands.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteAccessoryBar is built in code")
    }

    /// Shared with the selection's edit menu, so the two offer the same inline formats.
    static let inlineItems: [(title: String, symbol: String, command: NoteTouchCommand)] = [
        ("Bold", "bold", .inline(.bold)),
        ("Italic", "italic", .inline(.italic)),
        ("Strikethrough", "strikethrough", .inline(.strikethrough)),
        ("Code", "chevron.left.forwardslash.chevron.right", .inline(.inlineCode)),
        ("Link", "link", .inline(.link)),
    ]

    static func menu(
        title: String, items: [(title: String, symbol: String, command: NoteTouchCommand)],
        handler: @escaping (NoteTouchCommand) -> Void
    ) -> UIMenu {
        UIMenu(
            title: title,
            children: items.map { item in
                UIAction(title: item.title, image: UIImage(systemName: item.symbol)) { _ in
                    handler(item.command)
                }
            })
    }

    private func button(_ label: String, symbol: String, command: NoteTouchCommand) -> UIButton {
        sized(
            UIButton(
                configuration: .plain(),
                primaryAction: UIAction(image: UIImage(systemName: symbol)) { [handler] _ in
                    handler(command)
                }),
            label: label)
    }

    private func menuButton(
        _ label: String, symbol: String,
        items: [(title: String, symbol: String, command: NoteTouchCommand)]
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        let button = UIButton(configuration: configuration)
        button.menu = Self.menu(title: "", items: items, handler: handler)
        button.showsMenuAsPrimaryAction = true
        return sized(button, label: label)
    }

    private func sized(_ button: UIButton, label: String) -> UIButton {
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: NotesTheme.Size.accessoryButton).isActive = true
        return button
    }
}
