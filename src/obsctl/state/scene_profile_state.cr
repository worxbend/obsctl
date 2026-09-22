module Obsctl
  module State
    # One obsctl scene profile -- a named set of scene-visibility choices --
    # as clients see it.
    #
    # Nothing to do with an OBS profile, which is what `ObsSnapshot#profiles`
    # holds. `hidden` names the scenes this profile hides, spelled as OBS
    # spells them, and is empty for a profile that hides nothing.
    record SceneProfileState, name : String, hidden : Array(String) = [] of String
  end
end
