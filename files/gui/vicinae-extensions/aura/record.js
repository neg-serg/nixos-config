"use strict";

// Vicinae patches Module.prototype.require to provide these, and the extension has to be
// CommonJS for that patch to work (the same note stands in the hyprwhspr extension).
var React = require("react");
var cp = require("child_process");
var api = require("@vicinae/api");

// The diary's own recorder: it runs the diary's own recognition (elm/tools/RecordRunner.elm) and
// queues the entry for the diary to merge when it opens. The path is fixed because the diary lives
// in the user's src tree; AURA_RECORD overrides it.
var CLI = process.env.AURA_RECORD || process.env.HOME + "/src/emotion-diary/scripts/aura-record.mjs";
var DIARY = process.env.AURA_DIARY || "http://127.0.0.1:8080/";

function record(text) {
  return new Promise(function (resolve) {
    cp.execFile("node", [CLI, text], { timeout: 60000, maxBuffer: 1024 * 1024 }, function (error, stdout, stderr) {
      if (error) {
        resolve({ ok: false, detail: (stderr || error.message || "").trim() });
        return;
      }
      resolve({ ok: true, detail: (stdout || "").trim() });
    });
  });
}

function openDiary() {
  cp.execFile("xdg-open", [DIARY], function () { /* the browser is not our business */ });
}

function RecordCommand(props) {
  var text = ((props.arguments && props.arguments.text) || "").trim();
  var state = React.useState({ status: "running" });
  var answer = state[0];
  var setAnswer = state[1];

  React.useEffect(function () {
    var alive = true;
    if (!text) {
      setAnswer({ status: "empty" });
      return undefined;
    }
    record(text).then(function (result) {
      if (alive) setAnswer(result.ok ? { status: "done", detail: result.detail } : { status: "failed", detail: result.detail });
    });
    return function () { alive = false; };
  }, [text]);

  var markdown =
    answer.status === "running"
      ? "### Записываю\n\n> " + text
      : answer.status === "done"
        ? "### Записано в дневник\n\n```\n" + answer.detail + "\n```"
        : answer.status === "empty"
          ? "### Пусто\n\nНадиктуй или набери заметку — и повтори."
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
        React.createElement(api.Action, { title: "Скопировать заметку", onAction: function () { api.Clipboard.copy(text); } })
      )
    }
  );
}

function OpenCommand() {
  React.useEffect(openDiary, []);
  return null;
}

exports.default = function AuraCommand(props) {
  // the command name is in props.command? Vicinae tells the entry point which command ran through
  // the file it imported: `record.js` and `open.js` are separate entry points, so the name is the
  // module's own. Here the command is decided by the entry file name.
  return RecordCommand(props);
};
