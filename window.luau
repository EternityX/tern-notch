local HOME = tern.getenv("HOME") or ""
local DIR = HOME .. "/Library/Application Support/TernNotch"
local INBOX = DIR .. "/inbox"
local STATE = DIR .. "/state.json"
local APP = DIR .. "/TernNotch.app"
local APP_BINARY = APP .. "/Contents/MacOS/TernNotch"

local TICK_MS = 200
local REFRESH_TICKS = 5
local HEARTBEAT_S = 2
local LEASE_S = 5
local USAGE_EVERY_MS = 120000
local COMMAND_TTL_S = 30
local MAX_ITEMS = 30

local NULL = tern.json.null

local function opt(v)
	if v == nil or v == NULL then
		return nil
	end
	return v
end

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function nonempty(s: string?): string?
	if s == nil then
		return nil
	end
	local t = trim(s)
	return if t == "" then nil else t
end

local function strip_icons(s: string): string
	local ok, out = pcall(function()
		local parts = {}
		for _, cp in utf8.codes(s) do
			if not ((cp >= 0xE000 and cp <= 0xF8FF) or cp >= 0xF0000) then
				table.insert(parts, utf8.char(cp))
			end
		end
		return table.concat(parts)
	end)
	return trim(if ok then out else s)
end

local function clip(s: string, n: number): string
	local ok, out = pcall(function()
		local count = 0
		for pos, _ in utf8.codes(s) do
			count += 1
			if count > n then
				return string.sub(s, 1, pos - 1) .. "…"
			end
		end
		return s
	end)
	return if ok then out else string.sub(s, 1, n)
end

local function text_of(v): string
	v = opt(v)
	if v == nil then
		return ""
	end
	if type(v) == "string" then
		return v
	end
	if type(v) ~= "table" then
		return tostring(v)
	end
	if v.t ~= nil then
		if type(v.s) == "string" and string.find(v.s, "icon", 1, true) then
			return ""
		end
		return tostring(v.t)
	end
	local out = {}
	for _, part in v do
		table.insert(out, text_of(part))
	end
	return table.concat(out)
end

local function props(n)
	return if type(n) == "table" and type(n.p) == "table" then n.p else {}
end

local function walk(node, fn)
	if type(node) ~= "table" then
		return nil
	end
	local r = fn(node)
	if r ~= nil then
		return r
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local x = walk(child, fn)
			if x ~= nil then
				return x
			end
		end
	end
	return nil
end

local function by_role(root, role: string)
	return walk(root, function(n)
		return if props(n).role == role then n else nil
	end)
end

local function by_kind(root, kind: string)
	return walk(root, function(n)
		return if n.k == kind then n else nil
	end)
end

local function buttons_in(root)
	local out = tern.json.array()
	walk(root, function(n)
		local p = props(n)
		if n.k == "button" and p.disabled ~= true and p.hidden ~= true and p.busy ~= true then
			local act = if type(p.actions) == "table" and type(p.actions.click) == "string" then p.actions.click else "click"
			local label = nonempty(text_of(p.text)) or nonempty(text_of(p.spans)) or nonempty(text_of(p.title)) or act
			table.insert(out, {
				id = n.id,
				act = act,
				label = clip(label, 40),
				primary = if p.variant == "primary" then true else nil,
			})
		end
		return nil
	end)
	return out
end

local function options_in(list)
	local out = tern.json.array()
	if type(list.c) ~= "table" then
		return out
	end
	for _, item in list.c do
		local p = props(item)
		if item.k == "item" and #out < MAX_ITEMS then
			local role = if type(p.role) == "string" then p.role else ""
			local multi = string.find(role, "check", 1, true) ~= nil
			local kind = if string.find(role, "other", 1, true) then "other" elseif multi then "check" else "option"
			table.insert(out, {
				id = item.id,
				label = clip(text_of(p.label), 120),
				detail = nonempty(clip(text_of(p.detail), 200)),
				badge = nonempty(text_of(p.value)),
				kind = kind,
				multi = if multi then true else nil,
				checked = if p.icon == "check" then true else nil,
				disabled = if p.disabled == true then true else nil,
			})
		end
	end
	return out
end

local function parse_ask(n)
	local d = { kind = "ask" }
	local q = by_role(n, "omp.ask.question")
	if q then
		d.title = nonempty(text_of(props(q).text))
	end
	local tabs = by_role(n, "omp.ask.questions")
	if tabs and type(props(tabs).items) == "table" then
		local items = tern.json.array()
		for _, t in props(tabs).items do
			local label = text_of(t.label)
			local done = string.find(label, "✓", 1, true) ~= nil
			table.insert(items, {
				id = tostring(t.id),
				label = trim((string.gsub(label, "✓", ""))),
				done = if done then true else nil,
			})
		end
		local active = opt(props(tabs).active)
		d.tabs = { id = tabs.id, active = if active ~= nil then tostring(active) else nil, items = items }
	end
	local list = by_role(n, "omp.ask.options")
	if list then
		d.list = { id = list.id, items = options_in(list) }
	end
	local notice = by_role(n, "omp.ask.notice")
	if notice then
		d.notice = nonempty(text_of(props(notice).spans) .. text_of(props(notice).text))
	end
	local answers = by_role(n, "omp.ask.answers")
	if answers and type(props(answers).items) == "table" then
		local out = tern.json.array()
		for _, kv in props(answers).items do
			table.insert(out, { k = text_of(kv.k), v = clip(text_of(kv.v), 120) })
		end
		d.answers = out
	end
	d.buttons = buttons_in(n)
	return d
end

local function parse_answer(n)
	local d = { kind = "answer", input = true }
	local eyebrow = by_role(n, "omp.hook-editor.eyebrow")
	if eyebrow then
		d.eyebrow = nonempty(text_of(props(eyebrow).spans) .. text_of(props(eyebrow).text))
	end
	local q = by_role(n, "omp.ask.question")
	if q then
		d.title = nonempty(text_of(props(q).text))
	end
	d.buttons = buttons_in(n)
	return d
end

local function parse_overlay(layer)
	local ov = by_kind(layer, "overlay")
	if not ov then
		return nil
	end
	local ask = by_role(ov, "omp.editor.ask")
	if ask then
		return parse_ask(ask)
	end
	local d = { kind = "overlay", title = nonempty(text_of(props(ov).head)), buttons = buttons_in(ov) }
	local list = by_kind(ov, "list")
	if list then
		d.list = { id = list.id, items = options_in(list) }
	end
	return d
end

local function parse_dock(dock, r)
	local ctx = by_role(dock, "omp.composer.context")
	if ctx and type(props(ctx).value) == "number" then
		local p = props(ctx)
		r.context = {
			fraction = p.value,
			label = nonempty(text_of(p.label)),
			detail = nonempty(string.match(text_of(p.title), "\n([^\n]+)") or ""),
		}
	end
	local usage = by_role(dock, "omp.composer.usage")
	if usage then
		r.cost = nonempty(text_of(props(usage).spans) .. text_of(props(usage).text))
	end
	local model = by_role(dock, "omp.composer.model")
	if model then
		local name = walk(model, function(n)
			return if n.k == "text" and props(n).role == nil then n else nil
		end)
		if name then
			r.model = nonempty(text_of(props(name).spans) .. text_of(props(name).text)) or r.model
		end
		local effort = by_role(model, "omp.composer.model.effort")
		if effort and type(props(effort).level) == "string" then
			r.effort = props(effort).level
		end
	end
	local label = by_role(dock, "omp.working.label")
	if label then
		r.activity = nonempty(clip(text_of(props(label).spans) .. text_of(props(label).text), 120))
	end
	local line = by_role(dock, "omp.composer.line")
	local editor = if line then by_kind(line, "editor") else nil
	if editor then
		r.draft = text_of(props(editor).text) ~= ""
	end
	local hook = by_role(dock, "omp.overlay.hook-editor")
	local ask = by_role(dock, "omp.editor.ask")
	if hook then
		r.dialog = parse_answer(hook)
	elseif ask then
		r.dialog = parse_ask(ask)
	end
end

local function read_root(cx, pane: number, root: string)
	local ok, tree = pcall(function()
		return cx.session:surface(pane, { root = root, nodes = 2000 })
	end)
	if not ok or type(tree) ~= "table" or type(tree.surface) ~= "table" or tree.surface.role ~= "omp.session" then
		return nil
	end
	return tree.main or tree.dock or tree.layer
end

local composer = {}
local COMPOSER_FACTS = { "model", "effort", "context", "cost" }

local function basic(a)
	local e = {
		pane = a.pane,
		title = clip(strip_icons(opt(a.title) or ""), 80),
		state = opt(a.state) or "idle",
		program = opt(a.program) or opt(a.command),
		model = opt(a.model),
		cwd = opt(a.cwd),
		focused = if a.focused == true then true else nil,
		last = nonempty(clip(opt(a.last_message) or "", 280)),
	}
	local known = composer[a.pane]
	if known ~= nil then
		for _, key in COMPOSER_FACTS do
			if e[key] == nil then
				e[key] = known[key]
			end
		end
	end
	return e
end

local function inspect(cx, a)
	local e = basic(a)
	local dock = read_root(cx, a.pane, "dock")
	if dock then
		e.omp = true
		parse_dock(dock, e)
		if e.dialog == nil then
			local layer = read_root(cx, a.pane, "layer")
			if layer then
				e.dialog = parse_overlay(layer)
			end
		end
		local known = composer[a.pane] or {}
		for _, key in COMPOSER_FACTS do
			known[key] = e[key]
		end
		composer[a.pane] = known
	end
	return e
end

local function agents_of(cx)
	local ok, list = pcall(function()
		return cx.agents:list()
	end)
	return if ok and type(list) == "table" then list else {}
end

local function find_agent(cx, pane: number)
	for _, a in agents_of(cx) do
		if a.pane == pane then
			return a
		end
	end
	return nil
end

local quota = tern.json.array()

local function find_omp(): string?
	for _, path in {
		HOME .. "/Library/Application Support/Tern/omp/bin/omp",
		HOME .. "/.local/bin/omp",
		HOME .. "/.bun/bin/omp",
		"/opt/homebrew/bin/omp",
		"/usr/local/bin/omp",
	} do
		if tern.fs.exists(path) then
			return path
		end
	end
	return nil
end

local function parse_usage(text: string)
	local ok, doc = pcall(tern.json.decode, text)
	if not ok or type(doc) ~= "table" or type(doc.reports) ~= "table" then
		return nil
	end
	local out = tern.json.array()
	for _, rep in doc.reports do
		if type(rep) == "table" and type(rep.limits) == "table" then
			for _, lim in rep.limits do
				local amount = if type(lim.amount) == "table" then lim.amount else {}
				local used = nil
				if type(amount.usedFraction) == "number" then
					used = amount.usedFraction
				elseif type(amount.used) == "number" and type(amount.limit) == "number" and amount.limit > 0 then
					used = amount.used / amount.limit
				end
				if used ~= nil then
					local window = if type(lim.window) == "table" then lim.window else {}
					table.insert(out, {
						id = tostring(#out + 1) .. ":" .. tostring(opt(lim.id) or ""),
						provider = tostring(opt(rep.provider) or ""),
						label = text_of(lim.label),
						short = if opt(window.id) ~= nil then tostring(window.id) else nil,
						used = used,
						resetsAt = if type(window.resetsAt) == "number" then window.resetsAt else nil,
						status = opt(lim.status),
					})
				end
			end
		end
	end
	return out
end

local function refresh_usage()
	tern.timer(USAGE_EVERY_MS, refresh_usage)
	local omp = find_omp()
	if omp == nil then
		return
	end
	tern.process.run({ omp, "usage", "--json" }, { timeout_ms = 60000 }, function(res)
		if res.status == 0 then
			local parsed = parse_usage(res.stdout)
			if parsed ~= nil then
				quota = parsed
			end
		else
			tern.log.warn("tern-notch: omp usage failed", res.status, res.stderr)
		end
	end)
end

local BUILTIN_COMMANDS = require("./commands")
local CATALOG = DIR .. "/catalog.json"
local MODELS_EVERY_MS = 600000
local models = nil

local function command_file(path: string, name: string)
	local ok, text = pcall(tern.fs.read, path, 16384)
	if not ok then
		return nil
	end
	local description, hint = nil, nil
	local body = text
	local front = string.match(text, "^%-%-%-\n(.-)\n%-%-%-\n")
	if front then
		description = string.match(front, "\ndescription:%s*[\"']?([^\n\"']+)") or string.match(front, "^description:%s*[\"']?([^\n\"']+)")
		hint = string.match(front, "argument%-hint:%s*[\"']?([^\n\"']+)")
		body = string.sub(text, #front + 9)
	end
	if description == nil then
		description = string.match(body, "%s*([^\n]+)")
	end
	return { name = name, description = nonempty(clip(description or "", 80)), hint = nonempty(hint) }
end

local function commands_in(dir: string, out)
	local ok, names = pcall(tern.fs.list, dir)
	if not ok then
		return
	end
	for _, file in names do
		local name = string.match(file, "^([%w%-_:%.]+)%.md$")
		if name and #out < 60 then
			local entry = command_file(dir .. "/" .. file, name)
			if entry then
				table.insert(out, entry)
			end
		end
	end
end

local function write_catalog()
	local commands = tern.json.array()
	for _, c in BUILTIN_COMMANDS do
		table.insert(commands, c)
	end
	commands_in(HOME .. "/.omp/agent/commands", commands)
	tern.fs.mkdir(DIR)
	tern.fs.write(CATALOG, tern.json.encode({ v = 1, models = models or tern.json.array(), commands = commands }))
end

local function parse_models(text: string)
	local ok, doc = pcall(tern.json.decode, text)
	if not ok or type(doc) ~= "table" or type(doc.models) ~= "table" then
		return nil
	end
	local out = tern.json.array()
	for _, m in doc.models do
		if type(m) == "table" and type(m.selector) == "string" and (m.kind == nil or m.kind == "chat") then
			table.insert(out, {
				selector = m.selector,
				name = text_of(m.name),
				provider = tostring(opt(m.provider) or ""),
				thinking = if type(m.thinking) == "table" then m.thinking else nil,
			})
		end
	end
	return out
end

local function refresh_models()
	tern.timer(MODELS_EVERY_MS, refresh_models)
	local omp = find_omp()
	if omp == nil then
		write_catalog()
		return
	end
	tern.process.run({ omp, "models", "--json" }, { timeout_ms = 60000 }, function(res)
		if res.status == 0 then
			models = parse_models(res.stdout) or models
		else
			tern.log.warn("tern-notch: omp models failed", res.status, res.stderr)
		end
		write_catalog()
	end)
end

local FOLDER_STEP_MS = 1500
local folders = {}
local wanted = {}
local GIT_SCRIPT = [[
cd "$1" 2>/dev/null || exit 3
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 4
git symbolic-ref --short -q HEAD || git rev-parse --short HEAD
git diff HEAD --numstat 2>/dev/null | awk '{a += $1; d += $2; f++} END {print a + 0, d + 0, f + 0}'
]]

local function folder_step()
	tern.timer(FOLDER_STEP_MS, folder_step)
	local pick, oldest = nil, math.huge
	for cwd in folders do
		if not wanted[cwd] then
			folders[cwd] = nil
		end
	end
	for cwd in wanted do
		local at = if folders[cwd] then folders[cwd].at else -1
		if at < oldest then
			pick, oldest = cwd, at
		end
	end
	if pick == nil then
		return
	end
	local info = folders[pick] or {}
	info.at = tern.now()
	local commands = tern.json.array()
	commands_in(pick .. "/.omp/commands", commands)
	commands_in(pick .. "/.claude/commands", commands)
	info.commands = commands
	folders[pick] = info
	tern.process.run(
		{ "/bin/sh", "-c", GIT_SCRIPT, "sh", pick },
		{ timeout_ms = 10000, env = { PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" } },
		function(res)
			local entry = folders[pick]
			if entry == nil then
				return
			end
			if res.status == 0 then
				local branch, added, removed, files = string.match(res.stdout, "^([^\n]+)\n(%d+) (%d+) (%d+)")
				entry.branch = branch
				entry.added, entry.removed, entry.files = tonumber(added), tonumber(removed), tonumber(files)
			else
				entry.branch, entry.added, entry.removed, entry.files = nil, nil, nil, nil
			end
		end
	)
end

local function folders_for(cwds)
	local out = {}
	for cwd in cwds do
		local f = folders[cwd]
		if f then
			out[cwd] = {
				branch = f.branch,
				added = f.added,
				removed = f.removed,
				files = f.files,
				commands = f.commands,
			}
		end
	end
	return out
end

local toast = nil
local toast_seq = 0
local last_body = nil
local last_write = 0

local function notify(level: string, text: string)
	toast_seq += 1
	toast = { id = toast_seq, level = level, text = text, ["until"] = os.time() + 8 }
end

local function is_writer(cx): boolean
	local me = cx:window_key()
	local now = os.time()
	local ok, lease = pcall(tern.kv.get, "writer")
	lease = if ok and type(lease) == "table" then lease else nil
	if lease ~= nil and lease.key ~= me and now - (tonumber(lease.at) or 0) <= LEASE_S then
		return false
	end
	if lease == nil or lease.key ~= me or now - (tonumber(lease.at) or 0) >= 2 then
		pcall(tern.kv.set, "writer", { key = me, at = now })
	end
	return true
end

local inspected = {}
local INSPECT_MS = 12
local REREAD_MS = 900
local REREAD_WAITING_MS = 400

local function forget(pane)
	inspected[pane] = nil
end

local function publish(cx)
	local started = tern.now()
	local list = {}
	for _, a in agents_of(cx) do
		if opt(a.state) ~= "exited" and a.alive ~= false then
			table.insert(list, a)
		end
	end

	local function rank(a): number
		local seen = inspected[a.pane]
		if seen == nil or seen.state ~= opt(a.state) then
			return 0
		end
		return if opt(a.state) == "waiting_input" then 1 else 2
	end
	local order = table.clone(list)
	table.sort(order, function(x, y)
		local rx, ry = rank(x), rank(y)
		if rx ~= ry then
			return rx < ry
		end
		local sx, sy = inspected[x.pane], inspected[y.pane]
		return (if sx then sx.at else 0) < (if sy then sy.at else 0)
	end)
	local reads = 0
	for _, a in order do
		local seen = inspected[a.pane]
		local every = if opt(a.state) == "waiting_input" then REREAD_WAITING_MS else REREAD_MS
		local due = seen == nil or seen.state ~= opt(a.state) or tern.now() - seen.at >= every
		if due and (reads == 0 or tern.now() - started < INSPECT_MS) then
			inspected[a.pane] = { entry = inspect(cx, a), state = opt(a.state), at = tern.now() }
			reads += 1
		end
	end

	local agents = tern.json.array()
	local live = {}
	for _, a in list do
		live[a.pane] = true
		local seen = inspected[a.pane]
		if seen ~= nil and seen.state == opt(a.state) then
			local e = table.clone(seen.entry)
			local now = basic(a)
			e.title, e.focused, e.last = now.title, now.focused, now.last
			table.insert(agents, e)
		else
			table.insert(agents, basic(a))
		end
	end
	for pane in composer do
		if not live[pane] then
			composer[pane] = nil
		end
	end
	for pane in inspected do
		if not live[pane] then
			inspected[pane] = nil
		end
	end
	if toast ~= nil and os.time() > toast["until"] then
		toast = nil
	end

	local launch = HOME
	local focused = cx.session:focused()
	local pane = if focused ~= nil then cx.session:pane(focused) else nil
	if pane ~= nil and type(pane.cwd) == "string" and pane.cwd ~= "" and tern.fs.exists(pane.cwd) then
		launch = pane.cwd
	end
	wanted = { [launch] = true }
	for _, e in agents do
		if type(e.cwd) == "string" and e.cwd ~= "" then
			wanted[e.cwd] = true
		end
	end
	local folder_list = tern.json.array()
	for cwd, f in folders_for(wanted) do
		f.cwd = cwd
		table.insert(folder_list, f)
	end

	local state = {
		v = 1,
		agents = agents,
		quota = quota,
		launch = { cwd = launch },
		folders = folder_list,
		toast = if toast ~= nil then { id = toast.id, level = toast.level, text = toast.text } else nil,
	}
	local body = tern.json.encode(state)
	local now = os.time()
	if body == last_body and now - last_write < HEARTBEAT_S then
		return
	end
	state.at = now
	tern.fs.mkdir(DIR)
	tern.fs.write(STATE, tern.json.encode(state))
	last_body = body
	last_write = now
end

local refresh_soon

local function require_agent(cx, pane)
	if type(pane) ~= "number" or find_agent(cx, pane) == nil then
		error("That agent is gone", 0)
	end
	return pane
end

local function wait_for_answer_editor(pane: number, tries: number, text: string)
	tern.timer(120, function(cx)
		local a = find_agent(cx, pane)
		local e = if a then inspect(cx, a) else nil
		if e and e.dialog and e.dialog.kind == "answer" then
			cx:run(pane, text .. "\r")
			refresh_soon()
		elseif tries > 1 then
			wait_for_answer_editor(pane, tries - 1, text)
		else
			notify("error", "omp did not open the answer field")
		end
	end)
end

local function send_text(cx, pane: number, text: string)
	local e = inspect(cx, find_agent(cx, pane))
	local d = e.dialog
	local slash = string.sub(text, 1, 1) == "/"
	if d and d.kind == "answer" then
		cx:run(pane, text .. "\r")
	elseif d and d.kind == "ask" then
		if slash then
			error("Answer or skip the question first", 0)
		end
		local other = nil
		if d.list then
			for _, item in d.list.items do
				if item.kind == "other" then
					other = item
				end
			end
		end
		if other == nil then
			error("This question takes no typed answer", 0)
		end
		cx.session:event(pane, { ev = "activate", id = d.list.id, item = other.id })
		wait_for_answer_editor(pane, 15, text)
	elseif d then
		error("Close the open dialog in Tern first", 0)
	elseif slash then
		if e.draft then
			error("The composer has unsent text", 0)
		end
		cx:run(pane, text .. "\r")
	else
		local ok, err = pcall(function()
			cx.agents:ask(pane, text)
		end)
		if not ok then
			if e.draft then
				error(tostring(err), 0)
			end
			cx:run(pane, text .. "\r")
		end
	end
end

local function selector(v): string
	if type(v) ~= "string" or not string.match(v, "^[%w%-%._/:@]+$") then
		error("Not a model: " .. tostring(v), 0)
	end
	return v
end

local EFFORTS = { off = true, minimal = true, low = true, medium = true, high = true, xhigh = true, max = true, auto = true }

local function effort_level(v): string
	if type(v) ~= "string" or not EFFORTS[v] then
		error("Not a thinking level: " .. tostring(v), 0)
	end
	return v
end

local function handle(cx, cmd)
	local op = cmd.op
	if op == "pick" then
		local pane = require_agent(cx, cmd.pane)
		local ev = if cmd.mode == "select" then "select" else "activate"
		cx.session:event(pane, { ev = ev, id = tostring(cmd.list), item = tostring(cmd.item) })
	elseif op == "tab" then
		local pane = require_agent(cx, cmd.pane)
		cx.session:event(pane, { ev = "select", id = tostring(cmd.tabs), item = tostring(cmd.item) })
	elseif op == "button" then
		local pane = require_agent(cx, cmd.pane)
		cx.session:event(pane, { ev = "action", id = tostring(cmd.id), act = tostring(cmd.act) })
	elseif op == "send" then
		local pane = require_agent(cx, cmd.pane)
		local text = if type(cmd.text) == "string" then trim(cmd.text) else ""
		if text ~= "" then
			send_text(cx, pane, text)
		end
	elseif op == "focus" then
		cx.layout:focus(require_agent(cx, cmd.pane))
	elseif op == "model" then
		send_text(cx, require_agent(cx, cmd.pane), "/switch " .. selector(cmd.model))
	elseif op == "effort" then
		send_text(cx, require_agent(cx, cmd.pane), "/effort " .. effort_level(cmd.effort))
	elseif op == "start" then
		local text = if type(cmd.text) == "string" then trim(cmd.text) else ""
		local cwd = if type(cmd.cwd) == "string" and cmd.cwd ~= "" then cmd.cwd else HOME
		if text == "" then
			error("Type a prompt for the new agent", 0)
		end
		local command = "omp"
		if cmd.model ~= nil then
			command ..= " --model " .. selector(cmd.model)
		end
		if cmd.effort ~= nil then
			command ..= " --thinking " .. effort_level(cmd.effort)
		end
		cx.agents:start({ prompt = text, cwd = cwd, command = command, how = "tab" })
	end
end

local function poll_inbox(cx): boolean
	local ok, names = pcall(tern.fs.list, INBOX)
	if not ok then
		return false
	end
	local handled = false
	for _, name in names do
		if string.sub(name, 1, 1) ~= "." and string.sub(name, -5) == ".json" then
			local path = INBOX .. "/" .. name
			local read_ok, text = pcall(tern.fs.read, path, 65536)
			if pcall(tern.fs.remove, path) and read_ok then
				local decoded, cmd = pcall(tern.json.decode, text)
				if decoded and type(cmd) == "table" and os.time() - (tonumber(cmd.at) or 0) <= COMMAND_TTL_S then
					local done, err = pcall(handle, cx, cmd)
					if not done then
						notify("error", tostring(err))
					end
					if type(cmd.pane) == "number" then
						forget(cmd.pane)
					end
					handled = true
				end
			end
		end
	end
	return handled
end

local ticks = 0
local dirty = true

refresh_soon = function()
	dirty = true
end

local function tick(cx)
	tern.timer(TICK_MS, tick)
	local ok, err = pcall(function()
		if not is_writer(cx) then
			return
		end
		if poll_inbox(cx) then
			ticks = REFRESH_TICKS - 1
			return
		end
		ticks += 1
		if dirty or ticks >= REFRESH_TICKS then
			ticks = 0
			dirty = false
			publish(cx)
		end
	end)
	if not ok then
		tern.log.warn("tern-notch: tick failed", err)
	end
end

tern.on("agent_state", function()
	dirty = true
end)

tern.on("agent_finished", function()
	dirty = true
end)

local function launch(cx)
	tern.process.run({ "/usr/bin/xattr", "-dr", "com.apple.quarantine", APP }, function()
		tern.process.run({ "/usr/bin/open", "-g", APP }, function(res, cx2)
			if res.status ~= 0 then
				cx2:toast("error", "Agent Notch could not start", trim(res.stderr))
			end
		end)
	end)
end

local function ensure_app(cx, restart: boolean)
	if tern.runtime.os ~= "macos" then
		return
	end
	if tern.fs.exists(APP_BINARY) then
		if restart then
			tern.process.run({ "/usr/bin/pkill", "-x", "TernNotch" }, function(_, cx2)
				launch(cx2)
			end)
		else
			launch(cx)
		end
		return
	end
	cx:toast("info", "Building the Agent Notch helper…", "First run compiles TernNotch.app with swiftc.")
	tern.process.run({ "/bin/sh", tern.plugin.dir .. "/build.sh" }, { cwd = tern.plugin.dir, timeout_ms = 600000 }, function(res, cx2)
		if res.status == 0 then
			launch(cx2)
		else
			local lines = {}
			for line in string.gmatch(res.stderr, "[^\n]+") do
				table.insert(lines, line)
			end
			cx2:toast("error", "Agent Notch helper build failed", lines[#lines] or "see build.sh output")
		end
	end)
end

tern.command({
	id = "restart",
	title = "Agent Notch: restart helper",
	icon = "sparkle",
	run = function(cx)
		ensure_app(cx, true)
	end,
})

tern.command({
	id = "settings",
	title = "Agent Notch: settings",
	icon = "sparkle",
	run = function(cx)
		tern.process.run({ "/usr/bin/open", APP }, function(res, cx2)
			if res.status ~= 0 then
				cx2:toast("error", "Agent Notch settings could not open", trim(res.stderr))
			end
		end)
	end,
})

tern.fs.mkdir(INBOX)
tern.timer(50, function(cx)
	ensure_app(cx, false)
end)
tern.timer(400, tick)
tern.timer(1500, refresh_usage)
tern.timer(2500, refresh_models)
tern.timer(900, folder_step)
