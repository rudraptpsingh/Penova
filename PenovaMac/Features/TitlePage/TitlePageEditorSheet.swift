//
//  TitlePageEditorSheet.swift
//  Penova for Mac
//
//  Modal sheet over the library: form on the left for title-page
//  fields, live "paper" preview on the right showing how the title
//  page will render in PDF/FDX exports.
//

import SwiftUI
import SwiftData
import PenovaKit

struct TitlePageEditorSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title: String
    @State private var credit: String
    @State private var author: String
    @State private var source: String
    @State private var contact: String
    @State private var draftDate: String
    @State private var draftStage: String
    @State private var copyright: String
    @State private var notes: String

    init(project: Project) {
        self.project = project
        let tp = project.titlePage
        _title = State(initialValue: tp.title.isEmpty ? project.title : tp.title)
        _credit = State(initialValue: tp.credit.isEmpty ? "Written by" : tp.credit)
        _author = State(initialValue: tp.author)
        _source = State(initialValue: tp.source)
        _contact = State(initialValue: tp.contact.isEmpty ? project.contactBlock : tp.contact)
        _draftDate = State(initialValue: tp.draftDate)
        _draftStage = State(initialValue: tp.draftStage)
        _copyright = State(initialValue: tp.copyright)
        _notes = State(initialValue: tp.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(PenovaColor.ink4)
            HStack(spacing: 0) {
                form
                    .frame(width: 400)
                Divider().background(PenovaColor.ink4)
                preview
                    .frame(maxWidth: .infinity)
            }
            Divider().background(PenovaColor.ink4)
            footer
        }
        .background(PenovaColor.ink2)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(A11yID.titlePageSheet)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Title Page")
                    .font(PenovaFont.title)
                    .foregroundStyle(PenovaColor.snow)
                Text("Renders into PDF and FDX exports. WGA-standard layout.")
                    .font(.system(size: 13))
                    .foregroundStyle(PenovaColor.snow3)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PenovaColor.snow3)
                    .padding(8)
                    .background(PenovaColor.ink3)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fieldBlock(label: "Title", text: $title, font: PenovaFont.bodyLarge.weight(.semibold))
                HStack(spacing: 12) {
                    fieldBlock(label: "Credit", text: $credit, placeholder: "Written by")
                    fieldBlock(label: "Author", text: $author, placeholder: "Jane Writer")
                }
                fieldBlock(label: "Based on", text: $source,
                           placeholder: "Optional — \"Based on the novel by ...\"")
                contactBlock
                HStack(spacing: 12) {
                    fieldBlock(label: "Draft Date", text: $draftDate, placeholder: "1 May 2026")
                    draftStagePicker
                }
                fieldBlock(label: "Copyright", text: $copyright, placeholder: "© 2026 Author Name")
                notesBlock
            }
            .padding(20)
        }
    }

    private func fieldBlock(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        font: Font = PenovaFont.body
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(PenovaColor.snow)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(PenovaColor.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTACT")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            TextEditor(text: $contact)
                .scrollContentBackground(.hidden)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
                .frame(minHeight: 64)
                .padding(8)
                .background(PenovaColor.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
                .frame(minHeight: 48)
                .padding(8)
                .background(PenovaColor.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var draftStageOptions: [String] {
        var opts = ["—", "First Draft", "Production Draft"]
        // If the project has a current revision, surface that color
        // as a prefilled option ("Pink Revision", "Blue Revision",
        // …). Saves the user typing.
        if let last = project.revisionsByDate.first {
            opts.append("\(last.color.display) Revision")
        }
        return opts
    }

    private var draftStagePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRAFT STAGE")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            Menu {
                ForEach(draftStageOptions, id: \.self) { opt in
                    Button(opt) {
                        draftStage = (opt == "—") ? "" : opt
                    }
                }
            } label: {
                HStack {
                    Text(draftStage.isEmpty ? "—" : draftStage)
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(PenovaColor.snow4)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(PenovaColor.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var preview: some View {
        VStack {
            Spacer()
            paperPreview
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(PenovaColor.ink0)
    }

    private var paperPreview: some View {
        let ink = Color(red: 0.10, green: 0.08, blue: 0.05)
        return VStack {
            Spacer()
            VStack(spacing: 6) {
                Text(title.isEmpty ? "UNTITLED" : title.uppercased())
                    .font(.custom("RobotoMono-Medium", size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(ink)
                    .tracking(0.6)
                if !credit.isEmpty {
                    Text(credit)
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .foregroundStyle(ink)
                        .padding(.top, 12)
                }
                if !author.isEmpty {
                    Text(author)
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .fontWeight(.semibold)
                        .foregroundStyle(ink)
                }
                if !source.isEmpty {
                    Text(source)
                        .font(.custom("RobotoMono-Medium", size: 9))
                        .italic()
                        .foregroundStyle(ink.opacity(0.8))
                        .padding(.top, 18)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                if !contact.isEmpty {
                    Text(contact)
                        .font(.custom("RobotoMono-Medium", size: 8))
                        .foregroundStyle(ink.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if project.locked {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !draftStage.isEmpty {
                            Text(draftStage)
                        }
                        if !draftDate.isEmpty {
                            Text(draftDate)
                        }
                    }
                    .font(.custom("RobotoMono-Medium", size: 8))
                    .foregroundStyle(ink.opacity(0.7))
                }
            }
            if !copyright.isEmpty {
                Text(copyright)
                    .font(.custom("RobotoMono-Medium", size: 7))
                    .foregroundStyle(ink.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 32)
        .frame(width: 280, height: 360)
        .background(PenovaColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(PenovaColor.paperLine, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(PenovaColor.snow3)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: save) {
                Text("Save")
                    .font(PenovaFont.bodyMedium)
                    .foregroundStyle(PenovaColor.ink0)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(PenovaColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func save() {
        var tp = TitlePage(
            title: title.trimmingCharacters(in: .whitespaces),
            credit: credit.trimmingCharacters(in: .whitespaces),
            author: author.trimmingCharacters(in: .whitespaces),
            source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            draftDate: draftDate.trimmingCharacters(in: .whitespaces),
            draftStage: draftStage.trimmingCharacters(in: .whitespaces),
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            copyright: copyright.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        // Default credit so the renderer always has something to draw.
        if tp.credit.isEmpty { tp.credit = "Written by" }
        project.titlePage = tp
        project.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
