--[[
#########################################################################################################
#	@original mod:		overlay_mod      533622988                                                                                             #                  					                          
#	@original author: 	Stephanus van Zyl AKA Viceroy                                                                                                      # 
#	@me: gublluks												#									        
#########################################################################################################
--]]

local overlayHyperthermia2			= getTexture("media/textures/GUI/Hyperthermia2.png")
local overlayPain2				= getTexture("media/textures/GUI/Pain2.png"); 
local overlayPain3				= getTexture("media/textures/GUI/Pain3.png"); 
local overlayInjured2			= getTexture("media/textures/GUI/Injured2.png")

local screenX;
local screenY;
local overlayOffsetX;
local overlayOffsetY;

-- Tweak values listed below:
-- Current is merely used to blend smoothly.
-- Rate is how fast an overlay changes blend.
-- Cap is how many times you divide the opacity to lower it. 1 being not at all and 10 being ten times as dim.
-- Do NOT EVER set a cap to 0.

--VALUES

		--Hyperthermia2
local blendAmountHyperthermia2Current		= 0;
local blendAmountHyperthermia2Rate			= 0.002;
local blendCapHyperthermia2				= 5;
local blendAmountHyperthermia2Ideal			= 0;
local blendAmountHyperthermia2Lower			= 0;
local blendAmountHyperthermia2Upper		= 0;

		--Pain
local blendAmountPain2Current			= 0;
local blendAmountPain2Rate				= 0.03;
local blendCapPain2				= 4;
local blendAmountPain2Ideal				= 0;
local blendAmountPain2Lower			= 0;
local blendAmountPain2Upper			= 0;

local blendAmountPain3Current			= 0;
local blendAmountPain3Rate				= 0.04;
local blendCapPain3				= 4;
local blendAmountPain3Ideal				= 0;
local blendAmountPain3Lower			= 0;
local blendAmountPain3Upper			= 0;

		--Injured
local blendAmountInjured2Current			= 0;
local blendAmountInjured2Rate			= 0.03;
local blendCapInjured2				= 6;
local blendAmountInjured2Ideal			= 0;
local blendAmountInjured2Lower			= 0;
local blendAmountInjured2Upper			= 0;

--LEVEL

--[[내 수정--]]

local Hyperthermia2Level;
local Pain2Level;
local Injured2Level;

local function drawOverlay()

	player = getPlayer();

	if player then
	
--LEVELS ARE SET STARTING HERE

		--Hyperthermia2
		Hyperthermia2Level					= player:getMoodles():getMoodleLevel(MoodleType.Hyperth);
		blendAmountHyperthermia2Lower			= 0;
		blendAmountHyperthermia2Upper			= Hyperthermia2Level;

		--Pain
		Pain2Level					= player:getMoodles():getMoodleLevel(MoodleType.Pain);
		--Pain2
		blendAmountPain2Lower				= 0;
		blendAmountPain2Upper				= Pain2Level;
		--Pain3
		blendAmountPain3Lower				= 0;
		blendAmountPain3Upper				= Pain2Level;

		--Injured
		Injured2Level					= player:getMoodles():getMoodleLevel(MoodleType.Injured);
		--Injured2
		blendAmountInjured2Lower				= 0;
		blendAmountInjured2Upper				= Injured2Level;

-- LEVELS ARE SET ENDING HERE		
		


--OVERLAY
	
--Hyperthermia2
		if (Hyperthermia2Level < 2) then
				blendAmountHyperthermia2Current = 0;	
		end

		if (Hyperthermia2Level >= 2) then		
			if blendAmountHyperthermia2Current > blendAmountHyperthermia2Upper then			
				blendAmountHyperthermia2Ideal = blendAmountHyperthermia2Lower;
			
			elseif blendAmountHyperthermia2Current < blendAmountHyperthermia2Lower then
				blendAmountHyperthermia2Ideal = blendAmountHyperthermia2Upper;						
			end

		else
			if blendAmountHyperthermia2Current > 0 then
				blendAmountHyperthermia2Current = blendAmountHyperthermia2Current - blendAmountHyperthermia2Rate;
			end
			if blendAmountHyperthermia2Current <= 0 then
				blendAmountHyperthermia2Current = 0;
			end
		end

		if blendAmountHyperthermia2Current >= blendAmountHyperthermia2Ideal then	
			blendAmountHyperthermia2Current = blendAmountHyperthermia2Current - blendAmountHyperthermia2Rate;
		elseif blendAmountHyperthermia2Current <= blendAmountHyperthermia2Ideal then
			blendAmountHyperthermia2Current = blendAmountHyperthermia2Current + blendAmountHyperthermia2Rate;
		end		

--Pain2 overlay	
		if (Pain2Level < 2) then
				blendAmountPain2Current = 0;	
		end

		if (Pain2Level >= 2) then		
			if blendAmountPain2Current > blendAmountPain2Upper then			
				blendAmountPain2Ideal = blendAmountPain2Lower;
			
			elseif blendAmountPain2Current < blendAmountPain2Lower then
				blendAmountPain2Ideal = blendAmountPain2Upper;						
			end
		else
			if blendAmountPain2Current > 0 then
				blendAmountPain2Current = blendAmountPain2Current - blendAmountPain2Rate;
			end
			if blendAmountPain2Current <= 0 then
				blendAmountPain2Current = 0;
			end
		end

		if blendAmountPain2Current >= blendAmountPain2Ideal then	
			blendAmountPain2Current = blendAmountPain2Current - blendAmountPain2Rate;
		elseif blendAmountPain2Current <= blendAmountPain2Ideal then
			blendAmountPain2Current = blendAmountPain2Current + blendAmountPain2Rate;
		end
--Pain3 overlay	
		if (Pain2Level < 3) then
				blendAmountPain3Current = 0;	
		end

		if (Pain2Level >= 3) then		
			--This block sets our ideal states
			if blendAmountPain3Current > blendAmountPain3Upper then			
				blendAmountPain3Ideal = blendAmountPain3Lower;
			
			elseif blendAmountPain3Current < blendAmountPain3Lower then
				blendAmountPain3Ideal = blendAmountPain3Upper;						
			end

		else
			if blendAmountPain3Current > 0 then
				blendAmountPain3Current = blendAmountPain3Current - blendAmountPain3Rate;
			end
			if blendAmountPain3Current <= 0 then
				blendAmountPain3Current = 0;
			end
		end

		if blendAmountPain3Current >= blendAmountPain3Ideal then	
			blendAmountPain3Current = blendAmountPain3Current - blendAmountPain3Rate;
		elseif blendAmountPain3Current <= blendAmountPain3Ideal then
			blendAmountPain3Current = blendAmountPain3Current + blendAmountPain3Rate;
		end

--Injured2 overlay	
		if (Injured2Level < 2) then
				blendAmountInjured2Current = 0;	
		end

		if (Injured2Level >= 2) then		
			if blendAmountInjured2Current > blendAmountInjured2Upper then			
				blendAmountInjured2Ideal = blendAmountInjured2Lower;
			
			elseif blendAmountInjured2Current < blendAmountInjured2Lower then
				blendAmountInjured2Ideal = blendAmountInjured2Upper;						
			end
		else
			if blendAmountInjured2Current > 0 then
				blendAmountInjured2Current = blendAmountInjured2Current - blendAmountInjured2Rate;
			end
			if blendAmountInjured2Current <= 0 then
				blendAmountInjured2Current = 0;
			end
		end

		if blendAmountInjured2Current >= blendAmountInjured2Ideal then	
			blendAmountInjured2Current = blendAmountInjured2Current - blendAmountInjured2Rate;
		elseif blendAmountInjured2Current <= blendAmountInjured2Ideal then
			blendAmountInjured2Current = blendAmountInjured2Current + blendAmountInjured2Rate;
		end

		--Draw order block. DO NOT FORGET TO ADD OVERLAY HERE:
		--BOTTOM

--print("Overlays: Hyperthermia2: " .. blendAmountHyperthermia2Current);
		if blendAmountHyperthermia2Current > 0 then
		UIManager.DrawTexture( overlayHyperthermia2, 0, 0, screenX, screenY, (blendAmountHyperthermia2Current / blendCapHyperthermia2))
		end

--print("Overlays: Pain2: " .. blendAmountPain2Current);
		if blendAmountPain2Current > 0 then
		UIManager.DrawTexture( overlayPain2, 0, 0, screenX, screenY, (blendAmountPain2Current / blendCapPain2))
		end

--print("Overlays: Pain3: " .. blendAmountPain3Current);
		if blendAmountPain3Current > 0 then
		UIManager.DrawTexture( overlayPain3, 0, 0, screenX, screenY, (blendAmountPain3Current / blendCapPain3))
		end

--print("Overlays: Injured2: " .. blendAmountInjured2Current);
		if blendAmountInjured2Current > 0 then
		UIManager.DrawTexture( overlayInjured2, 0, 0, screenX, screenY, (blendAmountInjured2Current / blendCapInjured2))
		end

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