"use strict";

// Vicinae patches Module.prototype.require to provide these, and the extension has to be
// CommonJS for that patch to work (the same note stands in the hyprwhspr extension).
var React = require("react");
var cp = require("child_process");
var api = require("@vicinae/api");

// The diary's own recorder: it runs the diary's own recognition (elm/tools/RecordRunner.elm) and
// queues the entry for the diary to merge when it opens. The paths are fixed because the diary
// lives in the user's src tree — every knob is an environment variable, so the coupling is explicit
// and can be changed without touching this file:
//
//   AURA_RECORD       path to aura-record.mjs (default ~/src/emotion-diary/scripts/aura-record.mjs)
//   AURA_DIARY        diary URL (default http://127.0.0.1:8080/)
//   AURA_NO_BUILD=1   pass --no-build: skip the elm rebuild (faster, uses build/record.js as is)
//   AURA_OPEN_AFTER_RECORD=1  open the diary after a successful record (merging happens on open)
var fs = require("fs");
var CLI = process.env.AURA_RECORD || process.env.HOME + "/src/emotion-diary/scripts/aura-record.mjs";
var DIARY = process.env.AURA_DIARY || "http://127.0.0.1:8080/";
var NO_BUILD = process.env.AURA_NO_BUILD === "1";
var OPEN_AFTER_RECORD = process.env.AURA_OPEN_AFTER_RECORD === "1";

// With no text the recorder takes the clipboard, which is where hyprwhspr leaves a dictation
// (auto_copy_clipboard): dictate, open the launcher, press Enter, done.
function record(text) {
  return new Promise(function (resolve) {
    // A missing recorder is the one failure the person cannot guess from the
    // generic message: say which path was tried and which variable points it.
    if (!fs.existsSync(CLI)) {
      resolve({ ok: false, detail: "recorder not found: " + CLI + "\nset AURA_RECORD to the diary's scripts/aura-record.mjs" });
      return;
    }
    var args = [CLI].concat(NO_BUILD ? ["--no-build"] : []).concat(text ? [text] : []);
    cp.execFile("node", args, { timeout: 60000, maxBuffer: 4 * 1024 * 1024 }, function (error, stdout, stderr) {
      if (error) {
        resolve({ ok: false, detail: (stderr || stdout || error.message || "").trim() });
        return;
      }
      if (OPEN_AFTER_RECORD) openDiary();
      resolve({ ok: true, detail: (stdout || "").trim() });
    });
  });
}

function openDiary() {
  cp.execFile("xdg-open", [DIARY], function () { /* the browser is not our business */ });
}

function RecordCommand(props) {
  var typed = ((props.arguments && props.arguments.text) || "").trim();
  var state = React.useState({ status: "running" });
  var answer = state[0];
  var setAnswer = state[1];

  React.useEffect(function () {
    var alive = true;
    record(typed).then(function (result) {
      if (!alive) return;
      setAnswer(result.ok ? { status: "done", detail: result.detail } : { status: "failed", detail: result.detail });
    });
    return function () { alive = false; };
  }, [typed]);

  var markdown =
    answer.status === "running"
      ? "### Записываю\n\n> " + (typed || "текст из буфера обмена")
      : answer.status === "done"
        ? "### Записано в дневник\n\n```\n" + answer.detail + "\n```"
        : "### Не получилось\n\n```\n" + (answer.detail || "нет ответа") + "\n```";

  return React.createElement(
    api.Detail,
    {
      markdown: markdown,
      navigationTitle: "Aura — запись в дневник",
      actions: React.createElement(
        api.ActionPanel,
        null,
        React.createElement(api.Action, { title: "Открыть дневник", onAction: openDiary }),
        React.createElement(api.Action, {
          title: "Скопировать заметку",
          onAction: function () { api.Clipboard.copy(typed); }
        })
      )
    }
  );
}

exports.default = RecordCommand;
