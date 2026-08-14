--[[
#########################################################################################################
#	@mod:		overlay_mod                        					                                    #
#	@author: 	Stephanus van Zyl AKA Viceroy                                                           #
#	@link: 																						        #
#########################################################################################################
--]]

--local overlayBleeding			= getTexture("media/textures/GUI/vendetta_overlay_bleeding.png");

local overlayDamage				= getTexture("media/textures/GUI/damage.png");
local overlayPain				= getTexture("media/textures/GUI/pain.png");

local overlayHyperthermia		= getTexture("media/textures/GUI/hyperthermia.png");
local overlayHypothermia		= getTexture("media/textures/GUI/hypothermia.png");
--local overlayWetness			= getTexture("media/textures/GUI/vendetta_overlay_wetness.png");

local overlayTired				= getTexture("media/textures/GUI/tired.png");

local screenX;
local screenY;
local overlayOffsetX;
local overlayOffsetY;

-- Tweak values listed below:
-- Current is merely used to blend smoothly.
-- Rate is how fast an overlay changes blend.
-- Cap is how many times you divide the opacity to lower it. 1 being not at all and 10 being ten times as dim.
-- Do NOT EVER set a cap to 0.

local blendAmountPainCurrent			= 0;
local blendCapPain						= 4;

local blendAmountHealthCurrent			= 0;
local blendAmountHealthRate				= 0.005;
local blendCapHealth					= 4;

local blendAmountHyperthermiaCurrent	= 0;
local blendAmountHyperthermiaRate		= 0.01;
local blendCapHyperthermia				= 4;

local blendAmountHypothermiaCurrent		= 0;
local blendAmountHypothermiaRate		= 0.003;
local blendCapHypothermia				= 4;

local blendAmountTiredCurrent			= 0;
local blendAmountTiredRate				= 0.01;
local blendCapTired						= 4;

local painLevel;
local tiredLevel;
local healthLevel ;
local hyperthermiaLevel;
local hypothermiaLevel;

local function drawOverlay()

	player = getPlayer();
	
	if player then
	
		--LEVELS ARE SET STARTING HERE
		-- Pain
		painLevel 							= player:getMoodles():getMoodleLevel(MoodleType.Pain);

		
		--Damage
		healthLevel 					= player:getMoodles():getMoodleLevel(MoodleType.Injured);
		
		-- Hyperthermia
		hyperthermiaLevel 				= player:getMoodles():getMoodleLevel(MoodleType.Hyperth);
		
		-- Hypothermia
		hypothermiaLevel 				= player:getMoodles():getMoodleLevel(MoodleType.Hypothermia);
		
		--Tiredness
		tiredLevel						= player:getMoodles():getMoodleLevel(MoodleType.Tired);
		
		-- LEVELS ARE SET ENDING HERE
		
		
		
		--Pain overlay (sine pulse — throbs faster and brighter as pain increases)
		if painLevel < 1 then
			blendAmountPainCurrent = 0;
		else
			local speed     = 0.8 + painLevel * 0.4;
			local peakAlpha = 0.10 + (painLevel - 1) * 0.08;
			blendAmountPainCurrent = (math.sin(getTimestamp() / 1000 * speed * math.pi) * 0.5 + 0.5) * peakAlpha * blendCapPain;
		end
			

		
		--Health overlay
		if (healthLevel >= 0)then
			if blendAmountHealthCurrent >= healthLevel then
			
				blendAmountHealthCurrent = blendAmountHealthCurrent - blendAmountHealthRate;
			
			elseif blendAmountHealthCurrent < healthLevel then
		
				blendAmountHealthCurrent = blendAmountHealthCurrent + blendAmountHealthRate;
		
			end
		else
			if blendAmountHealthCurrent > 0 then
				blendAmountHealthCurrent = blendAmountHealthCurrent - blendAmountHealthRate;
			end
			if blendAmountHealthCurrent <= 0 then
				blendAmountHealthCurrent = 0;
			end
		end
		
		--Hyperthermia overlay
		if (hyperthermiaLevel >= 0)then
			if blendAmountHyperthermiaCurrent >= hyperthermiaLevel then
			
				blendAmountHyperthermiaCurrent = blendAmountHyperthermiaCurrent - blendAmountHyperthermiaRate;
			
			elseif blendAmountHyperthermiaCurrent < hyperthermiaLevel then
		
				blendAmountHyperthermiaCurrent = blendAmountHyperthermiaCurrent + blendAmountHyperthermiaRate;
		
			end
		else
			if blendAmountHyperthermiaCurrent > 0 then
				blendAmountHyperthermiaCurrent = blendAmountHyperthermiaCurrent - blendAmountHyperthermiaRate;
			end
			if blendAmountHyperthermiaCurrent <= 0 then
				blendAmountHyperthermiaCurrent = 0;
			end
		end

		--Hypothermia overlay
		if (hypothermiaLevel >= 0)then
			if blendAmountHypothermiaCurrent >= hypothermiaLevel then
			
				blendAmountHypothermiaCurrent = blendAmountHypothermiaCurrent - blendAmountHypothermiaRate;
			
			elseif blendAmountHypothermiaCurrent < hypothermiaLevel then
		
				blendAmountHypothermiaCurrent = blendAmountHypothermiaCurrent + blendAmountHypothermiaRate;
		
			end
		else
			if blendAmountHypothermiaCurrent > 0 then
				blendAmountHypothermiaCurrent = blendAmountHypothermiaCurrent - blendAmountHypothermiaRate;
			end
			if blendAmountHypothermiaCurrent <= 0 then
				blendAmountHypothermiaCurrent = 0;
			end
		end
		
		--Tired overlay
		if (tiredLevel >= 0)then
			if blendAmountTiredCurrent >= tiredLevel then
			
				blendAmountTiredCurrent = blendAmountTiredCurrent - blendAmountTiredRate;
			
			elseif blendAmountTiredCurrent < tiredLevel then
		
				blendAmountTiredCurrent = blendAmountTiredCurrent + blendAmountTiredRate;
		
			end
		else
			if blendAmountTiredCurrent > 0 then
				blendAmountTiredCurrent = blendAmountTiredCurrent - blendAmountTiredRate;
			end
			
			if blendAmountTiredCurrent <= 0 then
				blendAmountTiredCurrent = 0;
			end
		end
		
		--Draw order block. DO NOT FORGET TO ADD OVERLAY HERE:
		--BOTTOM
		if blendAmountTiredCurrent > 0 then
		UIManager.DrawTexture( overlayTired, 0, 0, screenX, screenY, (blendAmountTiredCurrent / blendCapTired))
		end
		--print("Overlays: Tired: " .. blendAmountTiredCurrent);
		if blendAmountHyperthermiaCurrent > 0 then
		UIManager.DrawTexture( overlayHyperthermia, 0, 0, screenX, screenY, (blendAmountHyperthermiaCurrent / blendCapHyperthermia))
		end
		--print("Overlays: Hyperthermia: " .. blendAmountHyperthermiaCurrent);
		if blendAmountHypothermiaCurrent > 0 then
		UIManager.DrawTexture( overlayHypothermia, 0, 0, screenX, screenY, (blendAmountHypothermiaCurrent / blendCapHypothermia))
		end
		--print("Overlays: Hypothermia: " .. blendAmountHypothermiaCurrent);
		if blendAmountHealthCurrent > 0 then
		UIManager.DrawTexture( overlayDamage, 0, 0, screenX, screenY, (blendAmountHealthCurrent / blendCapHealth))
		end
		--print("Overlays: Health: " .. blendAmountHealthCurrent);
		if blendAmountPainCurrent > 0 then
		UIManager.DrawTexture( overlayPain, 0, 0, screenX, screenY, (blendAmountPainCurrent / blendCapPain))
		end
		--print("Pain Blend Current: " .. blendAmountPainCurrent);
		--print("Pain Blend Ideal: " .. blendAmountPainIdeal);
		--print("Pain Blend Lower: " .. blendAmountPainLower);
		--print("Pain Blend Upper: " .. blendAmountPainUpper);
		--TOP
		
	end
	
	
end

local function screenSize()
	screenX = getCore():getScreenWidth();
	screenY = getCore():getScreenHeight();
end

local function screensSizeChange( _ox, _oy, x, y )
	screenX = x;
	screenY = y;
end

Events.OnGameBoot.Add( screenSize );
Events.OnResolutionChange.Add( screensSizeChange );
Events.OnPreUIDraw.Add( drawOverlay );