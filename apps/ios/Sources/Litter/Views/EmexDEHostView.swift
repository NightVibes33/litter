import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EmexDEHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        EmexDENavigationController(rootViewController: EmexDEProjectsViewController())
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct EmexDERouteView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .background(LitterTheme.background)
                .overlay(alignment: .bottom) { Divider() }

            EmexDEHostView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(LitterTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .litterFont(size: 17, weight: .semibold)
                    .foregroundColor(LitterTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(GlassCircleModifier())
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            Text("emexDE")
                .litterFont(size: 16, weight: .semibold)
                .foregroundColor(LitterTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private final class EmexDENavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

private final class EmexDEProjectsViewController: UITableViewController, UIDocumentPickerDelegate {
    private var projects: [URL] = []
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return documents.appendingPathComponent("EmexDE", isDirectory: true)
    }

    private var projectsURL: URL {
        rootURL.appendingPathComponent("Projects", isDirectory: true)
    }

    private var importsURL: URL {
        rootURL.appendingPathComponent("Imports", isDirectory: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Projects"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createProject)),
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"), style: .plain, target: self, action: #selector(importArchive))
        ]
        reloadProjects()
    }

    private func reloadProjects() {
        try? fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        let contents = (try? fileManager.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        projects = contents.filter { url in
            ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == true
        }.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(projects.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        cell.backgroundColor = .secondarySystemGroupedBackground
        if projects.isEmpty {
            cell.textLabel?.text = "No Projects"
            cell.detailTextLabel?.text = "Tap + to create an iOS project"
            cell.imageView?.image = UIImage(systemName: "hammer")
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let project = projects[indexPath.row]
            cell.textLabel?.text = project.lastPathComponent
            cell.detailTextLabel?.text = "Swift iOS app project"
            cell.imageView?.image = UIImage(systemName: "folder")
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !projects.isEmpty else { return }
        navigationController?.pushViewController(EmexDEProjectFilesViewController(projectURL: projects[indexPath.row]), animated: true)
    }

    @objc private func createProject() {
        let alert = UIAlertController(title: "New Project", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Project name"
            textField.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.createProject(named: name.isEmpty ? "Untitled" : name)
        })
        present(alert, animated: true)
    }

    private func createProject(named name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let projectURL = projectsURL.appendingPathComponent(safeName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
            try writeTemplateProject(to: projectURL, displayName: safeName)
            reloadProjects()
        } catch {
            presentError("Could not create project", message: error.localizedDescription)
        }
    }

    private func writeTemplateProject(to url: URL, displayName: String) throws {
        let sources = url.appendingPathComponent("Sources", isDirectory: true)
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        let appSwift = """
        import SwiftUI

        @main
        struct \(displayName.filter { $0.isLetter || $0.isNumber })App: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }
        """
        let contentSwift = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                VStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 48))
                    Text("\(displayName)")
                        .font(.title.bold())
                    Text("Created in emexDE")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        """
        try appSwift.write(to: sources.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try contentSwift.write(to: sources.appendingPathComponent("ContentView.swift"), atomically: true, encoding: .utf8)
    }

    @objc private func importArchive() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .data], asCopy: true)
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            try fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
            let destination = importsURL.appendingPathComponent(url.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            presentInfo("Import Saved", message: destination.lastPathComponent)
        } catch {
            presentError("Import Failed", message: error.localizedDescription)
        }
    }

    private func presentInfo(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentError(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private final class EmexDEProjectFilesViewController: UITableViewController {
    private let projectURL: URL
    private var files: [URL] = []
    private let fileManager = FileManager.default

    init(projectURL: URL) {
        self.projectURL = projectURL
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = projectURL.lastPathComponent
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        reloadFiles()
    }

    private func reloadFiles() {
        guard let enumerator = fileManager.enumerator(at: projectURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            files = []
            return
        }
        files = enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            return ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) == true ? url : nil
        }.sorted { lhs, rhs in
            relativePath(lhs).localizedCaseInsensitiveCompare(relativePath(rhs)) == .orderedAscending
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { files.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        let file = files[indexPath.row]
        cell.textLabel?.text = file.lastPathComponent
        cell.detailTextLabel?.text = relativePath(file)
        cell.imageView?.image = UIImage(systemName: "doc.text")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(EmexDETextPreviewViewController(fileURL: files[indexPath.row]), animated: true)
    }

    private func relativePath(_ url: URL) -> String {
        let base = projectURL.path.hasSuffix("/") ? projectURL.path : projectURL.path + "/"
        return url.path.replacingOccurrences(of: base, with: "")
    }
}

private final class EmexDETextPreviewViewController: UIViewController {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        let textView = UITextView(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isEditable = true
        textView.alwaysBounceVertical = true
        textView.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
