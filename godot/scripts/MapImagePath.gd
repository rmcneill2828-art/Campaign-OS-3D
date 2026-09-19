extends RefCounted
class_name MapImagePath
## ROADMAP.md's "Adventure map import" entry (2026-09-19) -- resolves a map name to a
## real raster image file on disk, if a DM has placed one, for GridManager.gd's own
## raster-floor rendering (see its _build_raster_floor()).
##
## PROVISIONAL convention, deliberately kept in exactly one place so it's easy to
## revise once real usage clarifies the actual DM workflow (see ROADMAP.md's own
## "decided v1 scope" -- this whole feature is a first slice, not a finished
## pipeline): a real map image lives at `engine-server/state/maps/<slugified-map-
## name>.<ext>` -- a sibling of this Godot project's own `res://` root, gitignored
## the same way `engine-server/state/encounter.json` already is (DM-provided runtime
## data, not source). The 2D app's own `state.maps[name].image` field is NOT this
## path -- it's an opaque key into that app's OWN browser-local IndexedDB image
## store (`CampaignOSImageStore`), unreachable from this Node-free, browser-free
## Godot process or from engine-server (also plain Node, no browser) -- so today the
## actual hand-off is manual: a DM exports/saves the same source image (e.g. a
## `pdftoppm`-rasterized adventure-module page they already calibrated in the 2D
## app's grid/wall tools) to this folder themselves, named to match the map. A
## same-machine, same-project convention like this is a deliberately small first
## step -- automating that hand-off (server-side, keyed off the 2D app's own image
## store somehow) is real future work, not assumed solved here.

const MAPS_DIR := "res://../engine-server/state/maps/"
const EXTENSIONS: Array[String] = ["jpg", "jpeg", "png"]

## Lowercase, non-alphanumeric runs collapsed to a single underscore, matching the
## same spirit as campaign.js's own slugify() and characterCreator.js's own
## fileNameForCharacter() sanitizing -- good enough for a filesystem-safe name, not
## trying to be a general-purpose slugifier.
static func slugify(map_name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9]+")
	var lower := map_name.to_lower()
	var slug := regex.sub(lower, "_", true)
	return slug.trim_prefix("_").trim_suffix("_")

## Returns the real, existing absolute path for `map_name`'s raster image, trying
## each extension in turn, or "" if none exists (the normal case for every
## hand-built or not-yet-provisioned map -- callers fall back to their own existing
## procedural/checkerboard rendering, same "degrade, don't fail" precedent every
## other missing-asset path in this project already follows).
static func resolve(map_name: String) -> String:
	var slug := slugify(map_name)
	if slug == "":
		return ""
	# globalize_path() doesn't resolve ".." itself (confirmed directly -- it just
	# concatenates the string); simplify_path() does, purely for a cleaner path if
	# this ever surfaces in a log/error message -- FileAccess itself resolves ".."
	# fine either way, since this is a real OS path handed to a real file-open call,
	# not Godot's own res:// virtual filesystem.
	var dir := ProjectSettings.globalize_path(MAPS_DIR).simplify_path()
	for ext in EXTENSIONS:
		var candidate := dir.path_join("%s.%s" % [slug, ext])
		if FileAccess.file_exists(candidate):
			return candidate
	return ""
