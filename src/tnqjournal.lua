local M = {
  paragraph_id = 0,
  line_id = 0,
  pages_seen = 0,
  buildpage_calls = 0,
  debug = true,
}

local node_id = node.id
local hlist_id = node_id('hlist')

local function log(msg)
  texio.write_nl('term and log', '[tnqjournal] ' .. msg)
end

local function count_lines(head)
  local n = 0
  for current in node.traverse_id(hlist_id, head) do
    if current.subtype == 1 or current.subtype == 0 then
      n = n + 1
    end
  end
  return n
end

local function pre_linebreak(head)
  M.paragraph_id = M.paragraph_id + 1
  return head
end

local function post_linebreak(head)
  local lines = count_lines(head)
  M.line_id = M.line_id + lines
  if M.debug and lines > 0 then
    log(string.format('paragraph=%d lines=%d cumulative-lines=%d',
      M.paragraph_id, lines, M.line_id))
  end
  return head
end

local function buildpage_filter(groupcode)
  M.buildpage_calls = M.buildpage_calls + 1
  return true
end

local function pre_output_filter(head)
  M.pages_seen = M.pages_seen + 1
  if M.debug then
    local height = node.dimensions(head)
    log(string.format('pre-output page=%d natural-height=%dsp buildpage-calls=%d',
      M.pages_seen, height or 0, M.buildpage_calls))
  end
  return head
end

function M.report_start()
  log('v3 node-level diagnostics active; floats remain out of scope')
end

function M.report_end()
  log(string.format(
    'summary paragraphs=%d lines=%d pages=%d buildpage-calls=%d',
    M.paragraph_id, M.line_id, M.pages_seen, M.buildpage_calls
  ))
end

function M.set_debug(value)
  M.debug = not not value
end

luatexbase.add_to_callback(
  'pre_linebreak_filter',
  pre_linebreak,
  'tnqjournal.pre_linebreak'
)

luatexbase.add_to_callback(
  'post_linebreak_filter',
  post_linebreak,
  'tnqjournal.post_linebreak'
)

luatexbase.add_to_callback(
  'buildpage_filter',
  buildpage_filter,
  'tnqjournal.buildpage_observer'
)

luatexbase.add_to_callback(
  'pre_output_filter',
  pre_output_filter,
  'tnqjournal.pre_output_observer'
)

return M
