local UIConstants = {}

-- Board layout constants
UIConstants.BOARD = {
	-- Slot positioning (relative to board center) - 1-based indexing
	SLOT_POSITIONS = {
		[1] = {x = -200, y = 100},   -- Top Left
		[2] = {x = 0, y = 100},      -- Top Center
		[3] = {x = 200, y = 100},    -- Top Right
		[4] = {x = -200, y = -100},  -- Bottom Left
		[5] = {x = 0, y = -100},     -- Bottom Center
		[6] = {x = 200, y = -100}    -- Bottom Right
	},
	
	-- Slot dimensions
	SLOT_SIZE = {
		width = 120,
		height = 160
	},
	
	-- Spacing between slots
	SLOT_SPACING = {
		horizontal = 220,
		vertical = 220
	}
}

-- Card display constants
UIConstants.CARD = {
	-- Card dimensions
	DIMENSIONS = {
		width = 100,
		height = 140
	},
	
	-- Card colors by rarity (canon set)
	RARITY_COLORS = {
		common = {r = 200, g = 200, b = 200},      -- Gray
		rare = {r = 0, g = 100, b = 255},          -- Blue
		epic = {r = 200, g = 0, b = 255},          -- Purple
		legendary = {r = 255, g = 165, b = 0}      -- Orange
	},
	
	-- Text colors
	TEXT_COLORS = {
		primary = {r = 255, g = 255, b = 255},     -- White
		secondary = {r = 200, g = 200, b = 200},   -- Light Gray
		accent = {r = 255, g = 255, b = 0}         -- Yellow
	}
}

-- Animation constants
UIConstants.ANIMATION = {
	-- Timing
	DURATION = {
		fast = 0.1,      -- Quick feedback
		normal = 0.3,    -- Standard transitions
		slow = 0.5,      -- Important changes
		very_slow = 1.0  -- Major state changes
	},
	
	-- Easing functions (string identifiers for now)
	EASING = {
		linear = "linear",
		quad = "quad",
		cubic = "cubic",
		bounce = "bounce"
	},
	
	-- Easing directions (string identifiers for now)
	DIRECTION = {
		["in"] = "in",
		out = "out",
		in_out = "in_out"
	}
}

-- Combat UI constants
UIConstants.COMBAT = {
	-- Turn indicator
	TURN_INDICATOR = {
		position = {x = 0, y = -300},
		size = {width = 200, height = 50}
	},
	
	-- Action buttons
	ACTION_BUTTONS = {
		position = {x = 0, y = 250},
		spacing = 20,
		size = {width = 80, height = 40}
	},
	
	-- Health bars
	HEALTH_BAR = {
		position = {x = 0, y = -80},
		size = {width = 100, height = 8},
		colors = {
			healthy = {r = 0, g = 255, b = 0},     -- Green
			warning = {r = 255, g = 255, b = 0},   -- Yellow
			critical = {r = 255, g = 0, b = 0}     -- Red
		}
	}
}

-- Menu constants
UIConstants.MENU = {
	-- Main menu
	MAIN_MENU = {
		position = {x = 0, y = 0},
		size = {width = 400, height = 500},
		button_spacing = 20
	},
	
	-- Collection menu
	COLLECTION = {
		position = {x = 0, y = 0},
		size = {width = 600, height = 400},
		card_grid = {
			columns = 4,
			rows = 3,
			spacing = 10
		}
	},
	
	-- Battle menu
	BATTLE = {
		position = {x = 0, y = 0},
		size = {width = 800, height = 600}
	}
}

-- Button constants
UIConstants.BUTTON = {
	-- Default button
	DEFAULT = {
		size = {width = 120, height = 40},
		corner_radius = 8,
		text_size = 18
	},
	
	-- Small button
	SMALL = {
		size = {width = 80, height = 30},
		corner_radius = 6,
		text_size = 14
	},
	
	-- Large button
	LARGE = {
		size = {width = 160, height = 50},
		corner_radius = 10,
		text_size = 20
	}
}

-- Text constants
UIConstants.TEXT = {
	-- Font sizes
	SIZES = {
		small = 12,
		normal = 16,
		large = 20,
		title = 24,
		header = 32
	},
	
	-- Font families (string identifiers for now)
	FONTS = {
		primary = "gotham",
		secondary = "gotham_bold",
		monospace = "code"
	}
}

-- Color scheme
UIConstants.COLORS = {
	-- Background colors
	BACKGROUND = {
		primary = {r = 40, g = 40, b = 40},        -- Dark gray
		secondary = {r = 60, g = 60, b = 60},      -- Medium gray
		tertiary = {r = 80, g = 80, b = 80}        -- Light gray
	},
	
	-- Accent colors
	ACCENT = {
		primary = {r = 0, g = 150, b = 255},       -- Blue
		secondary = {r = 255, g = 100, b = 0},     -- Orange
		success = {r = 0, g = 200, b = 0},         -- Green
		warning = {r = 255, g = 200, b = 0},       -- Yellow
		error = {r = 255, g = 50, b = 50}          -- Red
	}
}

return UIConstants
