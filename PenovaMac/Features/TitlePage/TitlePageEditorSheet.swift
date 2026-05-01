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
    @State private var byline: String = ""
    @State private var basedOn: String = ""
    @State private var contact: String
    @State private var draftDate: String = ""
    @State private var draftColor: String = "Production White"
    @State private var copyright: String = ""

    init(project: Project) {
        self.project = project
        _title = State(initialValue: project.title)
        _contact = State(initialValue: project.contactBlock)
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
                fieldBlock(label: "Written by", text: $byline)
                fieldBlock(label: "Based on", text: $basedOn, placeholder: "Optional")
                contactBlock
                HStack(spacing: 12) {
                    fieldBlock(label: "Draft Date", text: $draftDate, placeholder: "May 1, 2026")
                    fieldBlock(label: "Draft Color", text: $draftColor)
                }
                fieldBlock(label: "Copyright", text: $copyright)
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
            // Top contact block (top-left, screenwriter convention)
            HStack {
                if !contact.isEmpty {
                    Text(contact)
                        .font(.custom("RobotoMono-Medium", size: 9))
                        .foregroundStyle(ink.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            Spacer()
            VStack(spacing: 10) {
                Text(title.isEmpty ? "UNTITLED" : title.uppercased())
                    .font(.custom("RobotoMono-Medium", size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(ink)
                    .tracking(0.6)
                if !byline.isEmpty {
                    Text("written by")
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .foregroundStyle(ink)
                        .padding(.top, 12)
                    Text(byline)
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .fontWeight(.semibold)
                        .foregroundStyle(ink)
                }
                if !basedOn.isEmpty {
                    Text(basedOn)
                        .font(.custom("RobotoMono-Medium", size: 10))
                        .foregroundStyle(ink.opacity(0.8))
                        .padding(.top, 18)
                }
            }
            Spacer()
            HStack {
                Text(draftColor)
                Spacer()
                Text(draftDate)
            }
            .font(.custom("RobotoMono-Medium", size: 9))
            .foregroundStyle(ink.opacity(0.7))
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
        project.title = title.trimmingCharacters(in: .whitespaces)
        project.contactBlock = contact
        project.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
