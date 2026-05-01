//
//  TitlePageEditorScreen.swift
//  Penova
//
//  iOS form for editing a project's WGA-format title page. Mirrors
//  PenovaMac's TitlePageEditorSheet — same nine fields, same draft
//  stage dropdown — laid out as a vertical scroll for phone screens
//  with a compact "paper" preview at the bottom so the writer can
//  see how the title page will look in PDF/FDX exports.
//

import SwiftUI
import SwiftData
import PenovaKit

struct TitlePageEditorScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    @State private var title: String = ""
    @State private var credit: String = ""
    @State private var author: String = ""
    @State private var source: String = ""
    @State private var contact: String = ""
    @State private var draftDate: String = ""
    @State private var draftStage: String = ""
    @State private var copyright: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    PenovaTextField(label: "Title", text: $title,
                                    placeholder: "The Last Train")
                    PenovaTextField(label: "Credit", text: $credit,
                                    placeholder: "Written by")
                    PenovaTextField(label: "Author", text: $author,
                                    placeholder: "Jane Writer")
                    PenovaTextField(label: "Based on (Source)", text: $source,
                                    placeholder: "Optional")
                    multilineField(label: "Contact (title page)", text: $contact,
                                   placeholder: "name@email.com\n+1 555 0100\nAgent: ...")
                    PenovaTextField(label: "Draft date", text: $draftDate,
                                    placeholder: "1 May 2026")
                    draftStagePicker
                    PenovaTextField(label: "Copyright", text: $copyright,
                                    placeholder: "© 2026 Author Name")
                    multilineField(label: "Notes", text: $notes, placeholder: "Optional")
                    paperPreview
                    PenovaButton(title: "Save", variant: .primary) { save() }
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("Title page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear(perform: hydrate)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Lifecycle

    private func hydrate() {
        let tp = project.titlePage
        title = tp.title.isEmpty ? project.title : tp.title
        credit = tp.credit.isEmpty ? "Written by" : tp.credit
        author = tp.author
        source = tp.source
        contact = tp.contact.isEmpty ? project.contactBlock : tp.contact
        draftDate = tp.draftDate
        draftStage = tp.draftStage
        copyright = tp.copyright
        notes = tp.notes
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
        if tp.credit.isEmpty { tp.credit = "Written by" }
        project.titlePage = tp
        project.updatedAt = .now
        try? context.save()
        dismiss()
    }

    // MARK: - Components

    private var draftStageOptions: [String] {
        var opts = ["—", "First Draft", "Production Draft"]
        if let last = project.revisionsByDate.first {
            opts.append("\(last.color.display) Revision")
        }
        return opts
    }

    private var draftStagePicker: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text("Draft stage")
                .font(PenovaFont.labelCaps)
                .textCase(.uppercase)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Menu {
                ForEach(draftStageOptions, id: \.self) { opt in
                    Button(opt) { draftStage = (opt == "—") ? "" : opt }
                }
            } label: {
                HStack {
                    Text(draftStage.isEmpty ? "—" : draftStage)
                        .font(PenovaFont.bodyLarge)
                        .foregroundStyle(PenovaColor.snow)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(PenovaColor.snow4)
                }
                .padding(PenovaSpace.sm)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: PenovaRadius.sm)
                        .stroke(PenovaColor.ink4, lineWidth: 1)
                )
            }
        }
    }

    private func multilineField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(label)
                .font(PenovaFont.labelCaps)
                .textCase(.uppercase)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow4)
                        .padding(.horizontal, PenovaSpace.m)
                        .padding(.vertical, PenovaSpace.s + 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, PenovaSpace.s)
                    .padding(.vertical, PenovaSpace.xs)
                    .frame(minHeight: 96)
            }
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: PenovaRadius.sm)
                    .stroke(PenovaColor.ink4, lineWidth: 1)
            )
        }
    }

    // MARK: - Paper preview

    private var paperPreview: some View {
        let ink = Color(red: 0.10, green: 0.08, blue: 0.05)
        return VStack {
            Spacer()
            VStack(spacing: 4) {
                Text(title.isEmpty ? "UNTITLED" : title.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink)
                if !credit.isEmpty {
                    Text(credit)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ink)
                        .padding(.top, 8)
                }
                if !author.isEmpty {
                    Text(author)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ink)
                }
                if !source.isEmpty {
                    Text(source)
                        .font(.system(size: 8, design: .monospaced).italic())
                        .foregroundStyle(ink.opacity(0.8))
                        .padding(.top, 12)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                if !contact.isEmpty {
                    Text(contact)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if project.locked {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !draftStage.isEmpty { Text(draftStage) }
                        if !draftDate.isEmpty { Text(draftDate) }
                    }
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.7))
                }
            }
            if !copyright.isEmpty {
                Text(copyright)
                    .font(.system(size: 6, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Color(red: 0.96, green: 0.94, blue: 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
        )
    }
}
