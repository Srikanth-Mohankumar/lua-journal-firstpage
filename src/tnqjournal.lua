local M = { paragraph_id = 0 }

local function log(msg)
  texio.write_nl('term and log', '[tnqjournal] ' .. msg)
end

local function pre_linebreak(head)
  M.paragraph_id = M.paragraph_id + 1
  return head
end

function M.report_start()
  log('automatic native two-column flow active')
end

function M.report_end()
  log(string.format('paragraphs processed: %d', M.paragraph_id))
end

luatexbase.add_to_callback(
  'pre_linebreak_filter',
  pre_linebreak,
  'tnqjournal.paragraph_counter'
)

return M
