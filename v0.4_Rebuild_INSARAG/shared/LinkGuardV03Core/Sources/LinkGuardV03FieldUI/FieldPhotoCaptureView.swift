import LinkGuardV03Core
import SwiftUI

enum FieldPhotoCapturePreset: String, CaseIterable, Identifiable, Sendable {
    case scene
    case patient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scene:
            return "現場照片"
        case .patient:
            return "傷員照片"
        }
    }

    var defaultCaption: String {
        switch self {
        case .scene:
            return "Field photo evidence"
        case .patient:
            return "Patient photo evidence"
        }
    }

    var attachmentPrefix: String {
        switch self {
        case .scene:
            return "ATTACH"
        case .patient:
            return "PATIENT-PHOTO"
        }
    }
}

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

struct FieldPhotoCaptureView: View {
    let preset: FieldPhotoCapturePreset
    let onCancel: () -> Void
    let onSubmit: (String) -> Void

    @State private var selectedImage: UIImage?
    @State private var caption: String = ""
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label(selectedImage == nil ? "拍照或選取照片" : "更換照片", systemImage: "camera.fill")
                    }

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("尚未選擇照片")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(preset.title)
                }

                Section("回報文字") {
                    TextField("請輸入說明", text: $caption, axis: .vertical)
                }

                Section {
                    Button {
                        onSubmit(caption.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Label("送出照片回報", systemImage: "arrow.up.circle.fill")
                    }
                    .disabled(selectedImage == nil)
                }
            }
            .navigationTitle(preset.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .sheet(isPresented: $showingPicker) {
                CameraPickerView(image: $selectedImage)
            }
            .onAppear {
                if caption.isEmpty {
                    caption = preset.defaultCaption
                }
            }
        }
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        picker.allowsEditing = false

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier]
        } else {
            picker.sourceType = .photoLibrary
            picker.mediaTypes = [UTType.image.identifier]
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
    }
}
#else
struct FieldPhotoCaptureView: View {
    let preset: FieldPhotoCapturePreset
    let onCancel: () -> Void
    let onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(preset.title)
            Text("目前平台不支援相機拍照")
                .foregroundStyle(.secondary)
            Button("關閉", action: onCancel)
        }
        .padding()
    }
}
#endif
