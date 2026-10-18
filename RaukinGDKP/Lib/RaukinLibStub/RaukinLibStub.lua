-- RaukinLibStub - Private LibStub for RaukinGDKP addon
-- This is a namespaced version of LibStub to avoid conflicts with other addons
-- Based on LibStub by Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke

local RAUKINLIBSTUB_MAJOR, RAUKINLIBSTUB_MINOR = "RaukinLibStub", 2
local RaukinLibStub = _G[RAUKINLIBSTUB_MAJOR]

if not RaukinLibStub or RaukinLibStub.minor < RAUKINLIBSTUB_MINOR then
	RaukinLibStub = RaukinLibStub or {libs = {}, minors = {} }
	_G[RAUKINLIBSTUB_MAJOR] = RaukinLibStub
	RaukinLibStub.minor = RAUKINLIBSTUB_MINOR

	function RaukinLibStub:NewLibrary(major, minor)
		assert(type(major) == "string", "Bad argument #2 to `NewLibrary' (string expected)")
		minor = assert(tonumber(string.match(minor, "%d+")), "Minor version must either be a number or contain a number.")

		local oldminor = self.minors[major]
		if oldminor and oldminor >= minor then return nil end
		self.minors[major], self.libs[major] = minor, self.libs[major] or {}
		return self.libs[major], oldminor
	end

	function RaukinLibStub:GetLibrary(major, silent)
		if not self.libs[major] and not silent then
			error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
		end
		return self.libs[major], self.minors[major]
	end

	function RaukinLibStub:IterateLibraries() return pairs(self.libs) end
	setmetatable(RaukinLibStub, { __call = RaukinLibStub.GetLibrary })
end
