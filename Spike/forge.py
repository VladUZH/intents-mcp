#!/usr/bin/env python3
"""M0 spike: build UNSIGNED wrapper shortcuts for the test actions.

Throwaway code to answer tech-notes §9 by experiment; the product version is
Sources/ShortcutForge (M2). Signing and importing are separate, human-gated steps.

Each wrapper: Shortcut Input (JSON file) -> Get Dictionary -> Get Value per key
-> the App Intent -> Stop and Output (text).
"""
import plistlib
import sys
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

OUT = Path(__file__).resolve().parent / "out"
PREFIX = "imcp-spike-"


class Wrapper:
    def __init__(self, name):
        self.name = name
        self.actions = []

    def uid(self, label):
        return str(uuid5(NAMESPACE_URL, f"intents-mcp/spike/{self.name}/{label}")).upper()

    def add(self, identifier, label, **params):
        self.actions.append({"WFWorkflowActionIdentifier": identifier,
                             "WFWorkflowActionParameters": {"UUID": self.uid(label), **params}})

    def output(self, label, name):
        return attachment({"Type": "ActionOutput", "OutputUUID": self.uid(label), "OutputName": name})

    def plist(self):
        return {"WFWorkflowActions": self.actions,
                "WFWorkflowClientVersion": "2600",
                "WFWorkflowMinimumClientVersion": 900,
                "WFWorkflowMinimumClientVersionString": "900",
                "WFWorkflowTypes": [],
                "WFWorkflowImportQuestions": [],
                "WFQuickActionSurfaces": [],
                "WFWorkflowHasShortcutInputVariables": True,
                "WFWorkflowHasOutputFallback": False,
                "WFWorkflowInputContentItemClasses": ["WFStringContentItem", "WFDictionaryContentItem",
                                                      "WFGenericFileContentItem"],
                "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"],
                "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 61440}}


def attachment(value):
    return {"Value": value, "WFSerializationType": "WFTextTokenAttachment"}


def token_string(att):
    return {"WFSerializationType": "WFTextTokenString",
            "Value": {"string": "￼", "attachmentsByRange": {"{0, 1}": att["Value"]}}}


def descriptor(bundle, team, app, intent):
    return {"AppIntentDescriptor": {"TeamIdentifier": team, "BundleIdentifier": bundle,
                                    "Name": app, "AppIntentIdentifier": intent},
            "ShowWhenRun": False}


def json_input(w, keys):
    """Variant A (sweetrb): detect.dictionary + getvalueforkey per key."""
    w.add("is.workflow.actions.detect.dictionary", "request",
          WFInput=attachment({"Type": "ExtensionInput"}))
    for k in keys:
        w.add("is.workflow.actions.getvalueforkey", f"key-{k}", WFInput=w.output("request", "Dictionary"),
              WFDictionaryKey=k, WFGetDictionaryValueType="Value")
    return {k: w.output(f"key-{k}", "Dictionary Value") for k in keys}


def compact_input(keys):
    """Variant B (Dominic-DK): aggrandizements straight on Shortcut Input."""
    return {k: attachment({"Type": "ExtensionInput", "Aggrandizements": [
        {"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": "WFDictionaryContentItem"},
        {"Type": "WFDictionaryValueVariableAggrandizement", "DictionaryKey": k}]}) for k in keys}


def finish(w, label, name="Result"):
    w.add("is.workflow.actions.output", "out", WFOutput=token_string(w.output(label, name)))
    return w


def reminders_add(variant):
    w = Wrapper(f"reminders-add-{variant}")
    v = json_input(w, ["title", "dueDate"]) if variant == "A" else compact_input(["title", "dueDate"])
    w.add("com.apple.reminders.TTRCreateReminderAppIntent", "intent", CustomOutputName="Result",
          **descriptor("com.apple.reminders", "0000000000", "Reminders", "TTRCreateReminderAppIntent"),
          title=token_string(v["title"]), dueDate=token_string(v["dueDate"]))
    return finish(w, "intent")


def notes_create():
    w = Wrapper("notes-create")
    v = json_input(w, ["name", "contents"])
    w.add("com.apple.Notes.CreateNoteLinkAction", "intent", CustomOutputName="Result",
          **descriptor("com.apple.Notes", "0000000000", "Notes", "CreateNoteLinkAction"),
          name=token_string(v["name"]), contents=token_string(v["contents"]), interpretAsMarkdown=False)
    return finish(w, "intent")


def notes_append_find():
    """Entity via a chained Find: note chosen by exact title."""
    w = Wrapper("notes-append-find")
    v = json_input(w, ["note", "text"])
    w.add("is.workflow.actions.filter.notes", "find",
          AppIntentDescriptor={"TeamIdentifier": "0000000000", "BundleIdentifier": "com.apple.Notes",
                               "Name": "Notes", "AppIntentIdentifier": "NoteEntity"},
          WFContentItemLimitEnabled=True, WFContentItemLimitNumber=1,
          WFContentItemFilter={"WFSerializationType": "WFContentPredicateTableTemplate", "Value": {
              "WFActionParameterFilterPrefix": 1, "WFContentPredicateBoundedDate": False,
              "WFActionParameterFilterTemplates": [{"Property": "Name", "Operator": 4, "Removable": True,
                                                    "Values": {"String": token_string(v["note"])}}]}})
    w.add("com.apple.Notes.AppendToNoteLinkAction", "intent", CustomOutputName="Result",
          **descriptor("com.apple.Notes", "0000000000", "Notes", "AppendToNoteLinkAction"),
          operation="append", entity=w.output("find", "Notes"), text=token_string(v["text"]),
          ignoreWhitespace=False, interpretAsMarkdown=False)
    return finish(w, "intent")


def notes_append_id():
    """Entity straight from JSON: is an identifier string accepted? (§9 q4)"""
    w = Wrapper("notes-append-id")
    v = json_input(w, ["noteId", "text"])
    w.add("com.apple.Notes.AppendToNoteLinkAction", "intent", CustomOutputName="Result",
          **descriptor("com.apple.Notes", "0000000000", "Notes", "AppendToNoteLinkAction"),
          operation="append", entity=v["noteId"], text=token_string(v["text"]),
          ignoreWhitespace=False, interpretAsMarkdown=False)
    return finish(w, "intent")


def coteditor_create():
    w = Wrapper("coteditor-create")
    v = json_input(w, ["content"])
    w.add("com.coteditor.CotEditor.CreateDocumentIntent", "intent",
          **descriptor("com.coteditor.CotEditor", "HT3Z3A72WZ", "CotEditor", "CreateDocumentIntent"),
          content=token_string(v["content"]))
    w.add("is.workflow.actions.gettext", "done", WFTextActionText="COTEDITOR_OK")
    return finish(w, "done", "Text")


def macwhisper_transcribe():
    """File parameter: the audio file itself is the Shortcut Input."""
    w = Wrapper("macwhisper-transcribe")
    w.add("com.goodsnooze.MacWhisper.TranscribeAudioIntent", "intent", CustomOutputName="Result",
          **descriptor("com.goodsnooze.MacWhisper", "8Q7TMPA46J", "MacWhisper", "TranscribeAudioIntent"),
          audioFile=attachment({"Type": "ExtensionInput"}))
    return finish(w, "intent")


BUILDERS = {"reminders-add-A": lambda: reminders_add("A"), "reminders-add-B": lambda: reminders_add("B"),
            "notes-create": notes_create, "notes-append-find": notes_append_find,
            "notes-append-id": notes_append_id, "coteditor-create": coteditor_create,
            "macwhisper-transcribe": macwhisper_transcribe}

if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for key in sys.argv[1:] or BUILDERS:
        path = OUT / f"{PREFIX}{key}.unsigned.shortcut"
        # Binary plist: the signer sometimes rejects XML (shortcuts-playground#6).
        path.write_bytes(plistlib.dumps(BUILDERS[key]().plist(), fmt=plistlib.FMT_BINARY, sort_keys=False))
        print(path)
