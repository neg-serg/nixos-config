"use strict";

// The second entry point: opening the diary is a link, not a form.
var cp = require("child_process");

var DIARY = process.env.AURA_DIARY || "http://127.0.0.1:8080/";

exports.default = function OpenDiary() {
  cp.execFile("xdg-open", [DIARY], function () { /* nothing to report */ });
  return null;
};
