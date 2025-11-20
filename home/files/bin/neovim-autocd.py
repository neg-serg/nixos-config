#!/usr/bin/env python
"""Send current shell directory to a running Neovim (socket) as :lcd.

Usage:
  neovim-autocd.py

Description:
  Connects to Neovim via a socket at /tmp/nvim.sock and updates the
  editor's local directory (lcd) to the caller's current working directory.
  Intended to be used from a shell integration/alias.
"""
import os
import neovim

nvim = neovim.attach("socket", path="/tmp/nvim.sock")
nvim.vars["__autocd_cwd"] = os.getcwd()
nvim.command('execute "lcd" fnameescape(g:__autocd_cwd)')
del nvim.vars["__autocd_cwd"]
