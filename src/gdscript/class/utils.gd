extends RefCounted

const UFile = preload("res://addons/syntax_tags/src/remote/u_file.gd") #>remote
const URegex = preload("res://addons/syntax_tags/src/remote/u_regex.gd") #>remote u_regex.gd

const JSON_PATH = "res://addons/syntax_tags/tags.json"

const ANY_STRING = "const|var|@onready var|@export var|enum|class|func"

const TAG_CHAR = "#>"
const DEFAULT_COLOR_STRING = "35cc9b"
const DEFAULT_COLOR = Color(DEFAULT_COLOR_STRING)

class Config:
	const global_tag_color = "global_tag_color"
	const global_tag_mode = "global_tag_mode"
	const highlight_class = "highlight_class"
	const highlight_class_color = "highlight_class_color"
	const highlight_const = "highlight_const"
	const highlight_const_color = "highlight_const_color"

enum TagColorMode{
	GLOBAL,
	TAG,
	NONE
}

enum RegExTarget{
	CONST_VAR,
	CLASS,
	FUNC,
	ENUM,
	ANY
}

static func check_line_for_rebuild(line_text:String, line_text_last_state:String):
	if line_text.strip_edges() == "":
		return true
	if line_text.find(TAG_CHAR) > -1:
		return true
	if line_text_last_state.find(TAG_CHAR) > -1:
		return true
	if line_text.find("const ") > -1:
		return true
	if line_text.find("var ") > -1:
		return true
	
	return false

static func sort_keys(hl_info:Dictionary):
	var sorted_keys = hl_info.keys()
	sorted_keys.sort()
	var temp_dict = {}
	for key in sorted_keys:
		temp_dict[key] = hl_info.get(key)
	hl_info = temp_dict
	
	return hl_info

static func get_tags_data():
	var data = UFile.read_from_json(JSON_PATH)
	var tags = data.get("tags", {})
	return tags

static func get_config():
	var data = UFile.read_from_json(JSON_PATH)
	var config = data.get("config", {})
	return config

static func get_class_hl_data(config):
	var class_tag_data  = {
		"color": config.get(Config.highlight_class_color, Color.AQUA),
		"keyword":"const|vars",
		"menu":"None",
		"overwrite":false
	}
	return class_tag_data

static func get_const_hl_data(config):
	var const_tag_data  = {
		"color": config.get(Config.highlight_const_color, Color.CADET_BLUE),
		"keyword":"const",
		"menu":"None",
		"overwrite":false
	}
	return const_tag_data

static func get_global_tag_mode(selected):
	if selected is String:
		if selected == "Global":
			return 0
		elif selected == "Tag":
			return 1
		elif selected == "None":
			return 2
	elif selected is int:
		if selected == 0:
			return "Global"
		elif selected == 1:
			return "Tag"
		elif selected == 2:
			return "None"

static func get_regex_pattern(keywords:String, tag):
	if tag == "=CONST_HL":
		return "(?:const)\\s+([A-Z_0-9]+)\\s*[=:]" # const
	elif tag == "=CLASS_HL":
		return "(?:class|const|var)\\s+(?![A-Z_0-9]+\\s*[=:])([A-Z].*?)\\s*[=:]" # class
		#var pattern
		#if keywords == "const|vars":
			#pattern = "(?:const|var|@onready var|@export var)\\s+(.+?)\\s*[=:]"
	
	
	var regex_target = RegExTarget.CONST_VAR
	keywords = keywords.to_lower()
	if keywords == "any":
		regex_target = RegExTarget.ANY
		keywords = ANY_STRING
	if regex_target != RegExTarget.ANY:
		var keywords_array: PackedStringArray = keywords.split("|")
		var has_const_or_var = false
		var has_class = false
		var has_func = false
		var has_enum = false
		for keyword in keywords_array:
			if keyword == "func":
				has_func = true
			if keyword == "class":
				has_class = true
			if keyword == "enum":
				has_enum = true
			if keyword == "const" or keyword == "var":
				has_const_or_var = true
		if keywords.count("vars") == 1 and keywords.find("@onready") == -1 and keywords.find("@export") == -1:
			keywords = keywords.replace("vars", "var|@onready var|@export var")
		if int(has_func) + int(has_class) + int(has_enum) > 1:
			regex_target = RegExTarget.ANY
		elif has_func:
			regex_target = RegExTarget.FUNC
		elif has_class:
			regex_target = RegExTarget.CLASS
		elif has_enum:
			regex_target = RegExTarget.ENUM
		if has_const_or_var:
			if regex_target != RegExTarget.ANY and regex_target != RegExTarget.CONST_VAR:
				regex_target = RegExTarget.ANY
			elif regex_target != RegExTarget.ANY:
				regex_target = RegExTarget.CONST_VAR
	
	var keywords_array: PackedStringArray = keywords.split("|")
	var escaped_keywords_parts: Array = []
	for keyword_part in keywords_array:
		if not keyword_part.is_empty(): # Avoid issues with empty strings if input is like "var||const"
			escaped_keywords_parts.append(URegex.escape_regex_meta_characters(keyword_part))
	var combined_keywords_pattern: String
	if escaped_keywords_parts.is_empty():
		printerr("No valid keywords provided for regex.")
		return "(?!)"
	elif escaped_keywords_parts.size() == 1:
		combined_keywords_pattern = escaped_keywords_parts[0] # No need for group or | if only one
	else:
		combined_keywords_pattern = "(?:" + "|".join(escaped_keywords_parts) + ")"
	
	var escaped_tag_char = URegex.escape_regex_meta_characters(TAG_CHAR)
	var escaped_tag = URegex.escape_regex_meta_characters(tag)
	
	var pattern = "(?!)"
	if regex_target == RegExTarget.CONST_VAR:
		pattern = "^\\s*(?:(?:#\\s*)?static\\s+|#\\s*)?" + combined_keywords_pattern + "\\s+([a-zA-Z_][a-zA-Z0-9_]*)(?:\\s*:\\s*\\S+)?(?:\\s*(?:=|:=)\\s*.*?)?\\s*" + escaped_tag_char + "\\s*" + escaped_tag + "(?:\\s|$)"
	elif regex_target == RegExTarget.CLASS:
		pattern = "^\\s*(?:#)?class\\s+([A-Za-z_][A-Za-z0-9_]*)(?:\\s+extends\\s+(?:[A-Za-z_][A-Za-z0-9_.]*|\"[^\"]*\"))?\\s*:\\s*.*?" + escaped_tag_char + "\\s*" + escaped_tag + "(?:\\s|$)"
	elif regex_target == RegExTarget.FUNC:
		pattern = "^\\s*(?:(?:#\\s*)?static\\s+|#\\s*)?func\\s+([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(.*?\\)(?:\\s*->\\s*\\S+)?\\s*:.*?" + escaped_tag_char + "\\s*" + escaped_tag + "(?:\\s|$)"
	elif regex_target == RegExTarget.ENUM:
		pattern = "^\\s*(?:#)?enum\\s+([a-zA-Z_][a-zA-Z0-9_]*)(?:\\s*\\{.*?\\}|\\s*\\{|\\s*:)\\s*" + escaped_tag_char + "\\s*" + escaped_tag + "(?:\\s|$)"
	elif regex_target == RegExTarget.ANY: #CHONKER
		pattern = (
			"^\\s*(?:(?:#\\s*)?static\\s+|#\\s*)?" +                                  # Start of line, optional leading whitespace
			combined_keywords_pattern +                # Your combined keywords
			"\\s+" +                                   # One or more spaces after the keyword
			"([a-zA-Z_][a-zA-Z0-9_]*)" +               # CAPTURE GROUP 1: The name
			
			# Non-capturing group for the varying syntax between name and the '#tag'
			# Order matters: more specific/longer patterns first.
			"(?:" +
				# ---- BRANCH 1: Function signature (params, return type, colon) ----
				"(?:\\s*\\(.*?\\)(?:\\s*->\\s*\\S+)?\\s*:)" +
			"|" +
				# ---- BRANCH 2: Class definition with optional 'extends' ----
				# This needs to be before simple colon match if colon is part of extends
				"(?:\\s*(?:extends\\s+\\S+)?\\s*:)" + # Matches optional 'extends Something' then a colon
			"|" +
				# ---- BRANCH 3: Enum with inline body, tag is AFTER this structure `enum E {...} #tag` ----
				"(?:\\s*\\{.*?\\})" + # Non-greedy match for content within {}, then \s*#tag follows
			"|" +
				# ---- BRANCH 4: Enum with tag immediately after opening brace `enum E{ #tag` ----
				"(?:\\s*\\{)" + # Matches up to the opening brace
			"|" +
				# ---- BRANCH 5: Class (without extends) or Enum with simple colon (e.g., "enum E:") ----
				# This is a simpler colon match, placed after more complex colon patterns
				"(?:\\s*:)" +
			"|" +
				# ---- BRANCH 6: Variable/Constant specifics (type hint, assignment OR NOTHING for "var x #tag") ----
				"(?:(?:\\s*:\\s*\\S+)?(?:\\s*(?:=|:=)\\s*.*?)?)" +
			")" +
			
			"\\s*" + escaped_tag_char + "\\s*" +                              # Whitespace, '#', whitespace (for the comment start)
			escaped_tag +      # CAPTURE GROUP 2: The tag itself
			"(?:\\s|$)"                                # Trailing whitespace or end of line
			)
	
	return pattern
