-- svgxml.lua

-- Minimal XML parser for SVG. Preserves element order.

-- Each node: { tag, attr, children }

-- Strip XML noise: declarations, comments, CDATA, scripts

function strip_xml_noise(xml)
  xml = xml:gsub("<%?.-%?>", "")
  xml = xml:gsub("<!%-%-.-%-%->", "")
  xml = xml:gsub("<!%[CDATA%[.-%]%]>", "")
  xml = xml:gsub("<!DOCTYPE.->", "")
  xml = xml:gsub("<script[^>]*/>", "")
  xml = xml:gsub("<script[^>]*>.-</script>", "")
  return xml
end

-- Parse attributes from tag interior string

function parse_attrs(s)
  local attr = { }
  for k, v in s:gmatch("([%w_:%-]+)%s*=%s*\"(.-)\"") do
    attr[k] = v
  end
  for k, v in s:gmatch("([%w_:%-]+)%s*=%s*'(.-)'") do
    attr[k] = v
  end
  return attr
end

-- Create a node from tag interior string

function make_node(inside)
  local tag = inside:match("^(%S+)")
  return {
    tag = tag,
    attr = parse_attrs(inside),
    children = { }
  }
end

-- Process one opening or self-closing tag

function process_open_tag(inside, stack)
  local self_closing = inside:sub(-1) == "/"
  if self_closing then
    inside = inside:sub(1, -2)
  end
  local node = make_node(inside)
  local parent = stack[#stack]
  parent.children[#(parent.children) + 1] = node
  if not self_closing then
    stack[#stack + 1] = node
  end
end

-- Process one tag (open, close, or self-closing)

function process_tag(inside, stack)
  if inside:sub(1, 1) == "/" then
    table.remove(stack)
  else
    process_open_tag(inside, stack)
  end
end

-- Find next tag boundaries

function next_tag(xml, pos)
  local open = xml:find("<", pos)
  if not open then
    return nil
  end
  local close = xml:find(">", open)
  if not close then
    return nil
  end
  return xml:sub(open + 1, close - 1), close + 1
end

-- Create root node for parse tree

function make_root()
  return {
    tag = "root",
    attr = { },
    children = { }
  }
end

-- Parse XML string into ordered tree

function parse_xml(xml)
  xml = strip_xml_noise(xml)
  local root = make_root()
  local stack = { root }
  local pos = 1
  while pos <= #xml do
    local inside, npos = next_tag(xml, pos)
    if not inside then
      break
    end
    process_tag(inside, stack)
    pos = npos
  end
  return root
end

-- Find first child element by tag name

function find_child(node, tag)
  for _, child in ipairs(node.children) do
    if child.tag == tag then
      return child
    end
  end
end
