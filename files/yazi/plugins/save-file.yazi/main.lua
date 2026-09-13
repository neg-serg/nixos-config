local function entry(state, ...)
  local function log(msg)
    local f = io.open("/tmp/yazi_save_debug.log", "a")
    if f then
      f:write(os.date("%c") .. " > " .. tostring(msg) .. "\n")
      f:close()
    end
  end

  log("Plugin started (simplified).")
  
  local args = {}
  if state and type(state) == "table" and state.args then
      args = state.args
  elseif ... then
      args = { state, ... }
  end

  local mode = args[1]
  log("Mode: " .. tostring(mode))

  local output_path = os.getenv("YAZI_FILE_CHOOSER_PATH")
  local suggested = os.getenv("YAZI_SUGGESTED_FILENAME")
  local cwd = cx.active.current.cwd
  
  if not output_path then
    log("Error: No output path")
    ya.notify({ title = "Save File", content = "No output path set", timeout = 5.0, level = "error" })
    return
  end

  local function save(filename)
    log("Saving: " .. tostring(filename))
    local full_path = filename
    if string.sub(filename, 1, 1) ~= "/" then
       full_path = tostring(cwd) .. "/" .. filename
    end
    local out_file = io.open(output_path, "w")
    if out_file then
      out_file:write(full_path)
      out_file:close()
    end
    local f = io.open(full_path, "a")
    if f then f:close() end
    ya.manager_emit("quit", { "--no-confirm" })
  end

  if mode == "input" then
    local value, event = ya.input({
      title = "Save as (New File):", 
      value = suggested or "", 
      pos = { "top-center", y = 3, w = 40 }
    })
    if value then save(value) end
  elseif mode == "overwrite" then
    if suggested and suggested ~= "" then
       save(suggested)
    else
       local hovered = cx.active.current.hovered
       if hovered then
         save(tostring(hovered.name))
       else
         local value, event = ya.input({
            title = "Save as:", 
            value = "", 
            pos = { "top-center", y = 3, w = 40 }
         })
         if value then save(value) end
       end
    end
  else
    log("Unknown mode: " .. tostring(mode))
  end
end
return { entry = entry }
