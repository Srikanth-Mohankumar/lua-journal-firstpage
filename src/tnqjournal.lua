local M = {
  paragraph_id = 0,
  line_id = 0,
  payload_id = 0,
  mark_id = 0,
  origin_id = 0,
  mark_anchor_id = 0,
  transaction_id = 0,
  abstract_mode = false,
  abstract_first_line = false,
  abstract_last_decoration = nil,
  decoration_suspended = false,
  native_mode = false,
  late_abstract_width_errors = 0,
  forced_failure = nil,
  rollback_expected = nil,
}

local line_attribute = luatexbase.new_attribute("tnqjournal.line_id")
local paragraph_attribute = luatexbase.new_attribute("tnqjournal.paragraph_id")
local payload_attribute = luatexbase.new_attribute("tnqjournal.payload_id")
local mark_attribute = luatexbase.new_attribute("tnqjournal.mark_id")
local origin_attribute = luatexbase.new_attribute("tnqjournal.origin_id")
local mark_anchor_attribute = luatexbase.new_attribute("tnqjournal.mark_anchor")
local validate_register
local width_adjust_register
local first_main_width
local native_column_width

local hlist_id = node.id("hlist")
local glyph_id = node.id("glyph")
local vlist_id = node.id("vlist")
local whatsit_id = node.id("whatsit")
local mark_id = node.id("mark")
local write_subtype = node.subtype("write")
local dest_subtype = node.subtype("pdf_dest")
local user_defined_subtype = node.subtype("user_defined")
local mark_anchor_user_id = 22129
local mark_anchor_stride = 100000

local function is_mark_anchor(current)
  return current.id == whatsit_id and
    current.subtype == user_defined_subtype and
    current.user_id == mark_anchor_user_id
end

local function line_excerpt(line)
  local chars = {}
  for glyph in node.traverse_id(glyph_id, line.list) do
    if glyph.char and glyph.char > 31 then
      chars[#chars + 1] = utf8.char(glyph.char)
      if #chars >= 48 then
        break
      end
    end
  end
  return table.concat(chars)
end

-- The abstract panel is deliberately painted a line at a time.  A framed or
-- coloured vbox would make the complete abstract indivisible; these zero-net-
-- width decorations instead remain attached to the individual line hlists and
-- therefore survive an ordinary vertical split between any two lines.
local function pdf_literal(data)
  local literal = node.new("whatsit", "pdf_literal")
  literal.mode = 1
  literal.data = data
  return literal
end

local sp_per_bp = 65781.76
local pt = 65536

local function panel_path(line, first, last)
  local width = line.width
  if not (width and width > 0) then
    return ""
  end
  local w = width / sp_per_bp
  -- Later line backgrounds must never extend upward: PDF paints them after
  -- the preceding line and an upward overlap would erase that line's
  -- descenders. Continuity is owned exclusively by the preceding line's
  -- downward extension.
  local top_extra = (first and 13 or 5) * pt
  local bottom_extra = (last and 12.5 or 14) * pt
  local top = (math.max(line.height or 0, 0) + top_extra) / sp_per_bp
  local bottom = -(math.max(line.depth or 0, 0) + bottom_extra) / sp_per_bp
  local radius = math.min(7, (top - bottom) / 2, w / 2)
  local k = radius * 0.55228475
  local path = {}
  local function add(format, ...)
    path[#path + 1] = string.format(format, ...)
  end
  -- Darken makes the repeated split-safe rectangles idempotent: overlapping
  -- panel color remains unchanged, while glyphs already painted by a previous
  -- line stay dark instead of being covered by a later rectangle.
  add("q /TNQDarken gs 0.913725 0.921569 0.945098 rg")
  if first then
    add("%.4f %.4f m %.4f %.4f l", radius, top, w - radius, top)
    add("%.4f %.4f %.4f %.4f %.4f %.4f c",
      w - radius + k, top, w, top - radius + k, w, top - radius)
  else
    add("0 %.4f m %.4f %.4f l", top, w, top)
  end
  if last then
    add("%.4f %.4f l", w, bottom + radius)
    add("%.4f %.4f %.4f %.4f %.4f %.4f c",
      w, bottom + radius - k, w - radius + k, bottom, w - radius, bottom)
    add("%.4f %.4f l", radius, bottom)
    add("%.4f %.4f %.4f %.4f %.4f %.4f c",
      radius - k, bottom, 0, bottom + radius - k, 0, bottom + radius)
  else
    add("%.4f %.4f l 0 %.4f l", w, bottom, bottom)
  end
  if first then
    add("0 %.4f l", top - radius)
    add("0 %.4f %.4f %.4f %.4f %.4f c",
      top - radius + k, radius - k, top, radius, top)
  else
    add("0 %.4f l", top)
  end
  add("h f Q")
  return table.concat(path, " ")
end

local function decorate_abstract_line(line, first)
  local decoration = pdf_literal(panel_path(line, first, false))
  decoration.mode = 0
  local original = line.list
  decoration.next = original
  if original then
    original.prev = decoration
  end
  line.list = decoration
  return decoration
end

local function log(msg)
  texio.write_nl("term and log", "[tnqjournal] " .. msg)
end

local function set_result(ok)
  if validate_register then
    tex.setcount("global", validate_register, ok and 1 or 0)
  end
end

local function walk_nodes(head, action)
  if not head then
    return
  end
  for current in node.traverse(head) do
    action(current)
    if (current.id == hlist_id or current.id == vlist_id) and current.list then
      walk_nodes(current.list, action)
    end
  end
end

local function post_linebreak(head)
  M.paragraph_id = M.paragraph_id + 1
  for line in node.traverse_id(hlist_id, head) do
    M.line_id = M.line_id + 1
    node.set_attribute(line, line_attribute, M.line_id)
    node.set_attribute(line, paragraph_attribute, M.paragraph_id)
    if M.abstract_mode and not M.decoration_suspended then
      local first = M.abstract_first_line
      local decoration = decorate_abstract_line(line, first)
      M.abstract_first_line = false
      M.abstract_last_decoration = {
        literal = decoration,
        line = line,
        first = first,
      }
    end
    -- An anchor inserted while TeX is still collecting this paragraph starts
    -- with the previously completed line.  Once line breaking has located it,
    -- replace that provisional value with the containing line's stable ID.
    local function update_line_anchors(list)
      for current in node.traverse(list) do
        if is_mark_anchor(current) then
          local pair = math.floor((tonumber(current.value) or 0) /
            mark_anchor_stride)
          current.value = pair * mark_anchor_stride + M.line_id
        elseif (current.id == hlist_id or current.id == vlist_id) and
               current.list then
          update_line_anchors(current.list)
        end
      end
    end
    update_line_anchors(line.list)
    if M.native_mode and M.abstract_mode and not M.decoration_suspended and
       native_column_width and
       math.abs((line.width or 0) - native_column_width) > 2 then
      M.late_abstract_width_errors = M.late_abstract_width_errors + 1
      log(string.format(
        "TNQ-LATE-ABSTRACT line=%d got=%0.3f expected=%0.3f text=%s",
        M.line_id, (line.width or 0) / 65536,
        native_column_width / 65536, line_excerpt(line)))
    end
  end
  return head
end

function M.set_abstract_mode(enabled)
  enabled = not not enabled
  if enabled then
    M.abstract_first_line = true
    M.abstract_last_decoration = nil
  elseif M.abstract_mode and M.abstract_last_decoration then
    local last = M.abstract_last_decoration
    last.literal.data = panel_path(last.line, last.first, true)
    M.abstract_last_decoration = nil
  end
  M.abstract_mode = enabled
end

function M.suspend_decoration(enabled)
  M.decoration_suspended = not not enabled
end

local function collect_line_ids(box_number)
  local result = {}
  local box = tex.box[tonumber(box_number)]
  if not (box and box.list) then
    return result
  end

  local function walk(head)
    for current in node.traverse(head) do
      if current.id == hlist_id then
        local id = node.get_attribute(current, line_attribute)
        if id then
          result[#result + 1] = id
        end
      end
    end
  end

  walk(box.list)
  return result
end

local function collect_payload(box_number)
  local ids = {}
  local kinds = { write = 0, destination = 0, other = 0 }
  local box = tex.box[tonumber(box_number)]
  if not (box and box.list) then
    return ids, kinds
  end
  walk_nodes(box.list, function(current)
    if current.id == whatsit_id and not is_mark_anchor(current) then
      local id = node.get_attribute(current, payload_attribute)
      if id then
        ids[#ids + 1] = id
        if current.subtype == write_subtype then
          kinds.write = kinds.write + 1
        elseif current.subtype == dest_subtype then
          kinds.destination = kinds.destination + 1
        else
          kinds.other = kinds.other + 1
        end
      end
    end
  end)
  return ids, kinds
end

local function collect_marks(box_number)
  local ids = {}
  local box = tex.box[tonumber(box_number)]
  if not (box and box.list) then
    return ids
  end
  walk_nodes(box.list, function(current)
    if current.id == mark_id then
      local id = node.get_attribute(current, mark_attribute)
      if id then
        ids[#ids + 1] = id
      end
    end
  end)
  return ids
end

local function collect_origins(box_number)
  local ids = {}
  local box = tex.box[tonumber(box_number)]
  if not (box and box.list) then
    return ids
  end
  walk_nodes(box.list, function(current)
    local tracked_line = current.id == hlist_id and
      node.get_attribute(current, line_attribute)
    if tracked_line or
       (current.id == whatsit_id and not is_mark_anchor(current)) then
      local id = node.get_attribute(current, origin_attribute)
      if id then ids[#ids + 1] = id end
    end
  end)
  return ids
end

local function frequency(ids)
  local result = {}
  for _, id in ipairs(ids) do
    result[id] = (result[id] or 0) + 1
  end
  return result
end

-- A rollback assertion must examine the transaction inputs, rather than the
-- scratch fragments that validation is expected to reject.  This fingerprint
-- records the ordered node tree, its dimensions/subtypes, and our stable line
-- origins.  It deliberately excludes Lua userdata addresses, which differ for
-- copies and are not reproducible diagnostics.
local function box_fingerprint(box_number)
  local box = tex.box[tonumber(box_number)]
  if not box then
    return "void"
  end
  local hash = 2166136261
  local nodes = 0
  local function add(value)
    local data = tostring(value or "-") .. "|"
    for index = 1, #data do
      hash = ((hash ~ data:byte(index)) * 16777619) & 0xffffffff
    end
  end
  local function walk(head)
    for current in node.traverse(head) do
      nodes = nodes + 1
      add(current.id)
      add(current.subtype)
      add(current.width)
      add(current.height)
      add(current.depth)
      add(current.kern)
      add(current.penalty)
      add(node.get_attribute(current, line_attribute))
      add(node.get_attribute(current, paragraph_attribute))
      if (current.id == hlist_id or current.id == vlist_id) and current.list then
        walk(current.list)
      end
    end
  end
  add(box.width)
  add(box.height)
  add(box.depth)
  walk(box.list)
  return string.format("%08x/%d", hash, nodes)
end

local function collect_paragraph_ids(box_number)
  local result = {}
  local box = tex.box[tonumber(box_number)]
  if not (box and box.list) then
    return result
  end
  for current in node.traverse(box.list) do
    if current.id == hlist_id then
      local id = node.get_attribute(current, paragraph_attribute)
      if id then
        result[id] = true
      end
    end
  end
  return result
end

local function count_crossing_paragraphs(first, remainder)
  local in_first = collect_paragraph_ids(first)
  local in_remainder = collect_paragraph_ids(remainder)
  local count = 0
  for id in pairs(in_first) do
    if in_remainder[id] then
      count = count + 1
    end
  end
  return count
end

local function count_wrong_widths(box_number, expected, area, report)
  if not expected then
    return 0
  end
  local box = tex.box[tonumber(box_number)]
  if not (box and box.list) then
    return 0
  end
  local wrong = 0
  for current in node.traverse(box.list) do
    if current.id == hlist_id and
       node.get_attribute(current, line_attribute) and
       math.abs((current.width or 0) - expected) > 2 then
      wrong = wrong + 1
      if report then
        log(string.format(
          "TNQ-WIDTH-DETAIL area=%s line=%d par=%d got=%0.3f expected=%0.3f text=%s",
          area or "?", node.get_attribute(current, line_attribute) or -1,
          node.get_attribute(current, paragraph_attribute) or -1,
          (current.width or 0) / 65536, expected / 65536,
          line_excerpt(current)))
      end
    end
  end
  return wrong
end

local function validate_partition(input, first, remainder)
  local expected_ids = collect_line_ids(input)
  local first_ids = collect_line_ids(first)
  local remainder_ids = collect_line_ids(remainder)
  local actual_ids = {}
  for _, id in ipairs(first_ids) do
    actual_ids[#actual_ids + 1] = id
  end
  for _, id in ipairs(remainder_ids) do
    actual_ids[#actual_ids + 1] = id
  end

  local expected = frequency(expected_ids)
  local actual = frequency(first_ids)
  for id, count in pairs(frequency(remainder_ids)) do
    actual[id] = (actual[id] or 0) + count
  end

  local missing, duplicate = 0, 0
  for id, count in pairs(expected) do
    local seen = actual[id] or 0
    if seen < count then
      missing = missing + count - seen
    elseif seen > count then
      duplicate = duplicate + seen - count
    end
  end
  for id, count in pairs(actual) do
    if not expected[id] then
      duplicate = duplicate + count
    end
  end

  local misordered = 0
  local longest = math.max(#expected_ids, #actual_ids)
  for index = 1, longest do
    if expected_ids[index] ~= actual_ids[index] then
      misordered = misordered + 1
    end
  end

  return missing == 0 and duplicate == 0 and misordered == 0,
    missing, duplicate, misordered, #expected_ids, #first_ids,
    #remainder_ids
end

local function validate_payload_partition(input, first, remainder)
  local expected_ids, expected_kinds = collect_payload(input)
  local first_ids = collect_payload(first)
  local remainder_ids = collect_payload(remainder)
  local actual_ids = {}
  for _, id in ipairs(first_ids) do
    actual_ids[#actual_ids + 1] = id
  end
  for _, id in ipairs(remainder_ids) do
    actual_ids[#actual_ids + 1] = id
  end
  local expected = frequency(expected_ids)
  local actual = frequency(actual_ids)
  local missing, duplicate = 0, 0
  for id, count in pairs(expected) do
    local seen = actual[id] or 0
    if seen < count then
      missing = missing + count - seen
    elseif seen > count then
      duplicate = duplicate + seen - count
    end
  end
  for id, count in pairs(actual) do
    if not expected[id] then
      duplicate = duplicate + count
    end
  end
  local misordered = 0
  for index = 1, math.max(#expected_ids, #actual_ids) do
    if expected_ids[index] ~= actual_ids[index] then
      misordered = misordered + 1
    end
  end
  return missing == 0 and duplicate == 0 and misordered == 0,
    missing, duplicate, misordered, #expected_ids, #first_ids,
    #remainder_ids, expected_kinds
end

local function validate_mark_partition(input, first, remainder)
  local expected_ids = collect_marks(input)
  local first_ids = collect_marks(first)
  local remainder_ids = collect_marks(remainder)
  local actual_ids = {}
  for _, id in ipairs(first_ids) do actual_ids[#actual_ids + 1] = id end
  for _, id in ipairs(remainder_ids) do actual_ids[#actual_ids + 1] = id end
  local expected, actual = frequency(expected_ids), frequency(actual_ids)
  local missing, duplicate = 0, 0
  for id, count in pairs(expected) do
    local seen = actual[id] or 0
    if seen < count then missing = missing + count - seen end
    if seen > count then duplicate = duplicate + seen - count end
  end
  for id, count in pairs(actual) do
    if not expected[id] then duplicate = duplicate + count end
  end
  local misordered = 0
  for index = 1, math.max(#expected_ids, #actual_ids) do
    if expected_ids[index] ~= actual_ids[index] then
      misordered = misordered + 1
    end
  end
  return missing == 0 and duplicate == 0 and misordered == 0,
    missing, duplicate, misordered, #expected_ids, #first_ids, #remainder_ids
end

local function validate_origin_partition(input, first, remainder)
  local expected_ids = collect_origins(input)
  local first_ids = collect_origins(first)
  local remainder_ids = collect_origins(remainder)
  local actual_ids = {}
  for _, id in ipairs(first_ids) do actual_ids[#actual_ids + 1] = id end
  for _, id in ipairs(remainder_ids) do actual_ids[#actual_ids + 1] = id end
  local expected, actual = frequency(expected_ids), frequency(actual_ids)
  local missing, duplicate = 0, 0
  for id, count in pairs(expected) do
    local seen = actual[id] or 0
    if seen < count then missing = missing + count - seen end
    if seen > count then duplicate = duplicate + seen - count end
  end
  for id, count in pairs(actual) do
    if not expected[id] then duplicate = duplicate + count end
  end
  local misordered = 0
  for index = 1, math.max(#expected_ids, #actual_ids) do
    if expected_ids[index] ~= actual_ids[index] then
      misordered = misordered + 1
    end
  end
  return missing == 0 and duplicate == 0 and misordered == 0,
    missing, duplicate, misordered, #expected_ids, #first_ids, #remainder_ids
end

function M.setup(t)
  validate_register = assert(tonumber(t.validate), "bad validation register")
  width_adjust_register = assert(tonumber(t.width_adjust),
    "bad width-adjust register")
  local resources = pdf.getpageresources() or ""
  if not resources:find("/TNQDarken", 1, true) then
    pdf.setpageresources(resources ..
      " /ExtGState << /TNQDarken << /Type /ExtGState /BM /Darken >> >>")
  end
end

function M.set_widths(first, native)
  first_main_width = assert(tonumber(first), "bad first-page width")
  native_column_width = assert(tonumber(native), "bad native width")
end

function M.force_failure(domain)
  M.forced_failure = tostring(domain or "first")
  log("TNQ-TEST forced-failure=" .. M.forced_failure)
end

function M.write_mark_anchor()
  local anchor = node.new("whatsit", "user_defined")
  anchor.user_id = mark_anchor_user_id
  anchor.type = 100
  M.mark_anchor_id = M.mark_anchor_id + 1
  anchor.value = M.mark_anchor_id * mark_anchor_stride + M.line_id
  node.write(anchor)
end

-- Assigning an origin attribute is instrumentation, not structural ownership:
-- no node is detached, inserted, freed, or reordered.  TeX's \copy operation
-- carries the identifier into each transaction-owned scratch tree.
function M.prepare_payload(...)
  for _, box_number in ipairs({...}) do
    local box = tex.box[tonumber(box_number)]
    if box and box.list then
      local anchors, marks = {}, {}
      walk_nodes(box.list, function(current)
        if is_mark_anchor(current) then
          local value = tonumber(current.value) or 0
          anchors[#anchors + 1] = {
            pair = math.floor(value / mark_anchor_stride),
            line = value % mark_anchor_stride,
          }
        elseif current.id == mark_id then
          marks[#marks + 1] = current
        end
      end)
      table.sort(anchors, function(a, b) return a.pair < b.pair end)
      for index, mark in ipairs(marks) do
        if anchors[index] then
          node.set_attribute(mark, mark_anchor_attribute,
            anchors[index].line)
        end
      end
      if #marks > 0 then
        local values = {}
        for index = 1, #marks do
          values[index] = anchors[index] and tostring(anchors[index].line) or "?"
        end
        log("TNQ-MARK-ANCHORS lines=" .. table.concat(values, ","))
      end
      walk_nodes(box.list, function(current)
        local tracked_line = current.id == hlist_id and
          node.get_attribute(current, line_attribute)
        if (tracked_line or
            (current.id == whatsit_id and not is_mark_anchor(current))) and
           not node.get_attribute(current, origin_attribute) then
          M.origin_id = M.origin_id + 1
          node.set_attribute(current, origin_attribute, M.origin_id)
        end
        if current.id == whatsit_id and not is_mark_anchor(current) and
           not node.get_attribute(current, payload_attribute) then
          M.payload_id = M.payload_id + 1
          node.set_attribute(current, payload_attribute, M.payload_id)
        elseif current.id == mark_id and
               not node.get_attribute(current, mark_attribute) then
          M.mark_id = M.mark_id + 1
          node.set_attribute(current, mark_attribute, M.mark_id)
        end
      end)
    end
  end
end

function M.rehome_marks(page_number, tail_number)
  local page = tex.box[tonumber(page_number)]
  local tail = tex.box[tonumber(tail_number)]
  if not (page and page.list and tail) then
    log("TNQ-MARK-REHOME boundary=0 moved=0")
    return
  end
  local boundary = 0
  walk_nodes(page.list, function(current)
    if current.id == hlist_id then
      local id = node.get_attribute(current, line_attribute)
      if id and id > boundary then boundary = id end
    end
  end)

  local moved = {}
  local function strip_anchor_nodes(head)
    local current = head
    while current do
      local next_node = current.next
      if (current.id == hlist_id or current.id == vlist_id) and current.list then
        current.list = strip_anchor_nodes(current.list)
      end
      if is_mark_anchor(current) then
        head = node.remove(head, current)
        node.flush_node(current)
      end
      current = next_node
    end
    return head
  end
  local function extract_marks(box, may_move)
    local head = box.list
    local current = head
    while current do
      local next_node = current.next
      if current.id == mark_id then
        local anchor = node.get_attribute(current, mark_anchor_attribute)
        if may_move and anchor and anchor > boundary then
          head = node.remove(head, current)
          current.next, current.prev = nil, nil
          moved[#moved + 1] = { node = current, anchor = anchor }
        end
      end
      current = next_node
    end
    box.list = strip_anchor_nodes(head)
  end
  extract_marks(page, true)
  extract_marks(tail, false)

  local head = tail.list
  for _, entry in ipairs(moved) do
    local before, scan = nil, head
    while scan do
      local line = scan.id == hlist_id and
        node.get_attribute(scan, line_attribute)
      if line and line > entry.anchor then break end
      before = scan
      scan = scan.next
    end
    if before then
      head = node.insert_after(head, before, entry.node)
    elseif head then
      head = node.insert_before(head, head, entry.node)
    else
      head = entry.node
    end
  end
  tail.list = head
  log(string.format("TNQ-MARK-REHOME boundary=%d moved=%d", boundary, #moved))
end

function M.verify_rollback(main_input, stub_input)
  local expected = M.rollback_expected or {}
  local main = box_fingerprint(main_input)
  local stub = box_fingerprint(stub_input)
  local main_ok = expected.main == main
  local stub_ok = expected.stub == stub
  log(string.format(
    "TNQ-ROLLBACK main-preserved=%s stub-preserved=%s main=%s stub=%s",
    main_ok and "yes" or "no", stub_ok and "yes" or "no", main, stub))
  M.rollback_expected = nil
  return main_ok and stub_ok
end

function M.prepare_width_split(page, tail)
  local page_wrong = count_wrong_widths(page, first_main_width, "page", false)
  local tail_wrong = count_wrong_widths(tail, native_column_width, "tail", false)
  local action = 0
  if tail_wrong > 0 then
    action = -tail_wrong
  elseif page_wrong > 0 then
    action = page_wrong
  end
  tex.setcount("global", width_adjust_register, action)
end

function M.validate_first_page(main_input, main_page, main_tail,
                               stub_input, stub_page, stub_tail)
  M.transaction_id = M.transaction_id + 1
  M.rollback_expected = {
    main = box_fingerprint(main_input),
    stub = box_fingerprint(stub_input),
  }
  local main_ok, main_missing, main_duplicate, main_misordered,
    main_in, main_out, main_rem =
    validate_partition(main_input, main_page, main_tail)
  local stub_ok, stub_missing, stub_duplicate, stub_misordered,
    stub_in, stub_out, stub_rem =
    validate_partition(stub_input, stub_page, stub_tail)
  local main_payload_ok, main_payload_missing, main_payload_duplicate,
    main_payload_misordered, main_payload_in, main_payload_page,
    main_payload_tail, main_payload_kinds =
    validate_payload_partition(main_input, main_page, main_tail)
  local stub_payload_ok, stub_payload_missing, stub_payload_duplicate,
    stub_payload_misordered, stub_payload_in, stub_payload_page,
    stub_payload_tail, stub_payload_kinds =
    validate_payload_partition(stub_input, stub_page, stub_tail)
  local main_mark_ok, main_mark_missing, main_mark_duplicate,
    main_mark_misordered, main_mark_in, main_mark_page, main_mark_tail =
    validate_mark_partition(main_input, main_page, main_tail)
  local stub_mark_ok, stub_mark_missing, stub_mark_duplicate,
    stub_mark_misordered, stub_mark_in, stub_mark_page, stub_mark_tail =
    validate_mark_partition(stub_input, stub_page, stub_tail)
  local main_origin_ok, main_origin_missing, main_origin_duplicate,
    main_origin_misordered, main_origin_in, main_origin_page, main_origin_tail =
    validate_origin_partition(main_input, main_page, main_tail)
  local stub_origin_ok, stub_origin_missing, stub_origin_duplicate,
    stub_origin_misordered, stub_origin_in, stub_origin_page, stub_origin_tail =
    validate_origin_partition(stub_input, stub_page, stub_tail)
  local ok = main_ok and stub_ok and main_payload_ok and stub_payload_ok and
    main_mark_ok and stub_mark_ok and main_origin_ok and stub_origin_ok
  local crossing = count_crossing_paragraphs(main_page, main_tail)
  local page_width_errors = count_wrong_widths(
    main_page, first_main_width, "page", true)
  local tail_width_errors = count_wrong_widths(
    main_tail, native_column_width, "tail", true)
  ok = ok and page_width_errors == 0 and tail_width_errors == 0
  local forced = M.forced_failure == "first"
  if forced then
    ok = false
    M.forced_failure = nil
  end

  log(string.format(
    "TNQ-ACCOUNT tx=%d domain=main input=%d page=%d tail=%d",
    M.transaction_id, main_in, main_out, main_rem))
  log(string.format(
    "TNQ-INTEGRITY tx=%d domain=main missing=%d duplicate=%d order=%d",
    M.transaction_id, main_missing, main_duplicate, main_misordered))
  log(string.format(
    "TNQ-WHATSIT tx=%d domain=main input=%d page=%d tail=%d missing=%d duplicate=%d order=%d write=%d destination=%d other=%d",
    M.transaction_id, main_payload_in, main_payload_page, main_payload_tail,
    main_payload_missing, main_payload_duplicate, main_payload_misordered,
    main_payload_kinds.write, main_payload_kinds.destination,
    main_payload_kinds.other))
  log(string.format(
    "TNQ-PAYLOAD tx=%d domain=main write=%d destination=%d other=%d",
    M.transaction_id, main_payload_kinds.write,
    main_payload_kinds.destination, main_payload_kinds.other))
  log(string.format(
    "TNQ-MARK tx=%d domain=main input=%d page=%d tail=%d missing=%d duplicate=%d order=%d",
    M.transaction_id, main_mark_in, main_mark_page, main_mark_tail,
    main_mark_missing, main_mark_duplicate, main_mark_misordered))
  log(string.format(
    "TNQ-ORIGIN tx=%d domain=main input=%d page=%d tail=%d missing=%d duplicate=%d order=%d",
    M.transaction_id, main_origin_in, main_origin_page, main_origin_tail,
    main_origin_missing, main_origin_duplicate, main_origin_misordered))
  log(string.format("TNQ-CROSS tx=%d paragraphs=%d", M.transaction_id,
    crossing))
  log(string.format("TNQ-WIDTH tx=%d page-wrong=%d tail-wrong=%d",
    M.transaction_id, page_width_errors, tail_width_errors))
  log(string.format(
    "TNQ-ACCOUNT tx=%d domain=stub input=%d page=%d tail=%d",
    M.transaction_id, stub_in, stub_out, stub_rem))
  log(string.format(
    "TNQ-INTEGRITY tx=%d domain=stub missing=%d duplicate=%d order=%d",
    M.transaction_id, stub_missing, stub_duplicate, stub_misordered))
  log(string.format(
    "TNQ-WHATSIT tx=%d domain=stub input=%d page=%d tail=%d missing=%d duplicate=%d order=%d write=%d destination=%d other=%d",
    M.transaction_id, stub_payload_in, stub_payload_page, stub_payload_tail,
    stub_payload_missing, stub_payload_duplicate, stub_payload_misordered,
    stub_payload_kinds.write, stub_payload_kinds.destination,
    stub_payload_kinds.other))
  log(string.format(
    "TNQ-PAYLOAD tx=%d domain=stub write=%d destination=%d other=%d",
    M.transaction_id, stub_payload_kinds.write,
    stub_payload_kinds.destination, stub_payload_kinds.other))
  log(string.format(
    "TNQ-MARK tx=%d domain=stub input=%d page=%d tail=%d missing=%d duplicate=%d order=%d",
    M.transaction_id, stub_mark_in, stub_mark_page, stub_mark_tail,
    stub_mark_missing, stub_mark_duplicate, stub_mark_misordered))
  log(string.format(
    "TNQ-ORIGIN tx=%d domain=stub input=%d page=%d tail=%d missing=%d duplicate=%d order=%d",
    M.transaction_id, stub_origin_in, stub_origin_page, stub_origin_tail,
    stub_origin_missing, stub_origin_duplicate, stub_origin_misordered))
  log(string.format("TNQ-ACCOUNT tx=%d commit=%s",
    M.transaction_id, ok and "yes" or "no"))
  if forced then
    log(string.format("TNQ-TEST tx=%d rejected=forced", M.transaction_id))
  end
  if ok then
    M.rollback_expected = nil
  end
  set_result(ok)
end

function M.validate_stub(input, fragment, remainder)
  M.transaction_id = M.transaction_id + 1
  local ok, missing, duplicate, misordered, total, placed, held =
    validate_partition(input, fragment, remainder)
  local payload_ok, payload_missing, payload_duplicate, payload_misordered,
    payload_total, payload_placed, payload_held, payload_kinds =
    validate_payload_partition(input, fragment, remainder)
  ok = ok and payload_ok
  log(string.format(
    "TNQ-ACCOUNT tx=%d domain=stub-cont input=%d page=%d tail=%d",
    M.transaction_id, total, placed, held))
  log(string.format(
    "TNQ-INTEGRITY tx=%d domain=stub-cont missing=%d duplicate=%d order=%d",
    M.transaction_id, missing, duplicate, misordered))
  log(string.format(
    "TNQ-WHATSIT tx=%d domain=stub-cont input=%d page=%d tail=%d missing=%d duplicate=%d order=%d write=%d destination=%d other=%d",
    M.transaction_id, payload_total, payload_placed, payload_held,
    payload_missing, payload_duplicate, payload_misordered,
    payload_kinds.write, payload_kinds.destination, payload_kinds.other))
  log(string.format("TNQ-ACCOUNT tx=%d commit=%s",
    M.transaction_id, ok and "yes" or "no"))
  set_result(ok)
end

function M.report_start(available)
  log(string.format(
    "state=FIRST_BUILDING available=%0.5fpt mode=line-level",
    (tonumber(available) or 0) / 65536))
end

function M.report_commit(has_stub_tail)
  M.native_mode = true
  log("state=" .. (has_stub_tail and "STUB_PENDING" or "NATIVE"))
end

function M.report_end()
  log(string.format(
    "paragraphs=%d lines=%d payloads=%d marks=%d origins=%d transactions=%d late-abs-width=%d",
    M.paragraph_id, M.line_id, M.payload_id, M.mark_id, M.origin_id,
    M.transaction_id,
    M.late_abstract_width_errors))
end

luatexbase.add_to_callback(
  "post_linebreak_filter",
  post_linebreak,
  "tnqjournal.line_origin_ids"
)

return M
