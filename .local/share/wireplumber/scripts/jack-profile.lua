-- Follow the headphone jack on cards that split Speaker and Headphones into two
-- mutually exclusive profiles (Intel SOF/UCM on binstar) instead of two ports on
-- one sink.
--
-- Stock WirePlumber picks a profile by priority and never looks at the jack:
-- both profiles always report "available" (each also carries the HDMI outputs).
-- Worse, it re-picks on every EnumProfile change, and an external monitor's
-- modeset changes HDMI audio availability — so a monitor reset silently moved
-- audio from the headphones to the speakers. Measured 2026-10-01: a card
-- `change` fired exactly when DP-1 went 60 -> 120 Hz.
--
-- This hook decides the profile from the jack on every pick, whatever triggered
-- it, and triggers a pick when the jack moves. It replaces ~/.scripts/jack-watch,
-- which drove pactl from outside and also forced the default sink (pulling audio
-- off bluetooth on every jack event). The default sink stays WirePlumber's.
--
-- No profile names are hardcoded: the card's own routes say which profiles
-- carry Headphones and which carry Speaker.

cutils = require ("common-utils")
log = Log.open_topic ("s-device")

-- The profile the jack calls for, or nil when this device does not split the two
-- outputs (every other card, bluetooth included, is left to the stock hooks).
local function jackProfile (device)
  local hp, spk
  for p in device:iterate_params ("EnumRoute") do
    local r = cutils.parseParam (p, "EnumRoute")
    if r and r.direction == "Output" and type (r.profiles) == "table" then
      if r.name:find ("Headphones") then
        hp = r
      elseif r.name:find ("Speaker") then
        spk = r
      end
    end
  end
  if not hp or not spk then
    return nil
  end
  -- a card with both on one profile switches ports itself; not ours to touch
  for _, i in ipairs (hp.profiles) do
    if cutils.arrayContains (spk.profiles, i) then
      return nil
    end
  end

  local route = hp.available == "yes" and hp or spk
  local best = nil
  for p in device:iterate_params ("EnumProfile") do
    local prof = cutils.parseParam (p, "EnumProfile")
    if prof and prof.name ~= "pro-audio" and cutils.arrayContains (route.profiles, prof.index)
        and (best == nil or prof.priority > best.priority) then
      best = prof
    end
  end
  return best
end

-- Before the priority rules (device.profile.priority.rules), which only know a
-- fixed order. Stored-profile restore is off (50-laptop-speaker.conf), so
-- nothing earlier claims the pick.
SimpleEventHook {
  name = "device/find-jack-profile",
  after = "device/find-stored-profile",
  before = "device/find-preferred-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    if event:get_data ("selected-profile") then
      return
    end
    local device = event:get_subject ()
    local prof = jackProfile (device)
    if prof then
      log:info (device, string.format ("jack: selecting profile '%s' (%d)",
          prof.name, prof.index))
      event:set_data ("selected-profile", prof)
    end
  end
}:register ()

-- A jack moving changes route availability (EnumRoute), not the profile list,
-- so the stock select-profile trigger never fires for it. apply-profile skips
-- the switch when the pick equals the active profile, so extra picks are free.
SimpleEventHook {
  name = "device/select-profile-on-jack",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "EnumRoute" },
    },
  },
  execute = function (event)
    local device = event:get_subject ()
    if jackProfile (device) then
      event:get_source ():call ("push-event", "select-profile", device, nil)
    end
  end
}:register ()
