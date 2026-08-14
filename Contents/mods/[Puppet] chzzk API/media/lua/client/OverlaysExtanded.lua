--[[
#########################################################################################################
#	@original mod:		overlay_mod      533622988                                                                                             #                  					                          
#	@original author: 	Stephanus van Zyl AKA Viceroy                                                                                                      # 
#	@me: gublluks												#									        
#########################################################################################################
--]]

local overlayWet				= getTexture("media/textures/GUI/wet.png");
local overlayWet2				= getTexture("media/textures/GUI/wet2.png");
local overlayWet3				= getTexture("media/textures/GUI/wet3.png");
local overlayBleeding			= getTexture("media/textures/GUI/bleeding.png"); 
local overlayBleeding2			= getTexture("media/textures/GUI/bleeding2.png"); 
local overlayBleeding3			= getTexture("media/textures/GUI/bleeding3.png"); 
local overlayZombie			= getTexture("media/textures/GUI/zombie.png");

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

		--Wet
local blendAmountWetCurrent			= 0;
local blendAmountWetRate				= 0.003;
local blendCapWet					= 4;

local blendAmountWet2Current			= 0;
local blendAmountWet2Rate				= 0.002;
local blendCapWet2				= 4;

local blendAmountWet3Current			= 0;
local blendAmountWet3Rate				= 0.001;
local blendCapWet3				= 4;

		--Bleeding
local blendAmountBleedingCurrent			= 0;
local blendAmountBleedingRate			= 0.01;
local blendCapBleeding				= 4;
local blendAmountBleedingIdeal			= 0;
local blendAmountBleedingLower			= 0;
local blendAmountBleedingUpper			= 0;

local blendAmountBleeding2Current			= 0;
local blendAmountBleeding2Rate			= 0.01;
local blendCapBleeding2				= 4;
local blendAmountBleeding2Ideal			= 0;
local blendAmountBleeding2Lower			= 0;
local blendAmountBleeding2Upper			= 0;

local blendAmountBleeding3Current			= 0;
local blendAmountBleeding3Rate			= 0.05;
local blendCapBleeding3				= 6;
local blendAmountBleeding3Ideal			= 0;
local blendAmountBleeding3Lower			= 0;
local blendAmountBleeding3Upper			= 0;

		--Zombie
local blendAmountZombieCurrent			= 0;
local blendCapZombie				= 4;

--LEVEL

--[[내 수정--]]

local wetLevel;
local BleedingLevel;
local ZombieLevel;

local function drawOverlay()

	player = getPlayer();

	if player then
	
--LEVELS ARE SET STARTING HERE

		--Wet
		wetLevel						= player:getMoodles():getMoodleLevel(MoodleType.Wet);
		
		--Bleeding
		BleedingLevel					= player:getMoodles():getMoodleLevel(MoodleType.Bleeding);
		blendAmountBleedingLower				= 0;
		blendAmountBleedingUpper				= BleedingLevel;
		--Bleeding2
		blendAmountBleeding2Lower				= 0;
		blendAmountBleeding2Upper				= BleedingLevel;
		--Bleeding3
		blendAmountBleeding3Lower				= 0;
		blendAmountBleeding3Upper				= BleedingLevel;

		--Zombie
		ZombieLevel					= player:getMoodles():getMoodleLevel(MoodleType.Zombie);

-- LEVELS ARE SET ENDING HERE		
		



--OVERLAY

--Wet overlay
		if (wetLevel >= 0)then
			if blendAmountWetCurrent >= wetLevel then			
				blendAmountWetCurrent = blendAmountWetCurrent - blendAmountWetRate;
			
			elseif blendAmountWetCurrent < wetLevel then		
				blendAmountWetCurrent = blendAmountWetCurrent + blendAmountWetRate;
		
			end
		else
			if blendAmountWetCurrent > 0 then
				blendAmountWetCurrent = blendAmountWetCurrent - blendAmountWetRate;
			end
			if blendAmountWetCurrent <= 0 then
				blendAmountWetCurrent = 0;
			end
		end
--Wet2 overlay
		if (wetLevel < 2) then
				blendAmountWet2Current = 0;	
		end
		if (wetLevel >= 2)then
			if blendAmountWet2Current >= wetLevel then			
				blendAmountWet2Current = blendAmountWet2Current - blendAmountWet2Rate;
			
			elseif blendAmountWet2Current < wetLevel then		
				blendAmountWet2Current = blendAmountWet2Current + blendAmountWet2Rate;		
			end
		else
			if blendAmountWet2Current > 0 then
				blendAmountWet2Current = blendAmountWet2Current - blendAmountWet2Rate;
			end
			if blendAmountWet2Current <= 0 then
				blendAmountWet2Current = 0;
			end
		end
--Wet3 overlay
		if (wetLevel < 3) then
				blendAmountWet3Current = 0;	
		end
		if (wetLevel >= 3)then
			if blendAmountWet3Current >= wetLevel then			
				blendAmountWet3Current = blendAmountWet3Current - blendAmountWet3Rate;
			
			elseif blendAmountWet3Current < wetLevel then		
				blendAmountWet3Current = blendAmountWet3Current + blendAmountWet3Rate;		
			end
		else
			if blendAmountWet3Current > 0 then
				blendAmountWet3Current = blendAmountWet3Current - blendAmountWet3Rate;
			end
			if blendAmountWet3Current <= 0 then
				blendAmountWet3Current = 0;
			end
		end


--Bleeding overlay		
		if (BleedingLevel >= 0) then		
			--This block sets our ideal states
			if blendAmountBleedingCurrent > blendAmountBleedingUpper then			
				blendAmountBleedingIdeal = blendAmountBleedingLower;
			
			elseif blendAmountBleedingCurrent < blendAmountBleedingLower then
				blendAmountBleedingIdeal = blendAmountBleedingUpper;						
			end

		--This is our blend after the player has died
		else
			if blendAmountBleedingCurrent >= 0 then	
				blendAmountBleedingCurrent = blendAmountBleedingCurrent - blendAmountBleedingRate;
			end
			if blendAmountBleedingCurrent < 0 then
				blendAmountBleedingCurrent = 0;
			end
		end		
		--This is our regular Bleeding blend
		if blendAmountBleedingCurrent >= blendAmountBleedingIdeal then	
			blendAmountBleedingCurrent = blendAmountBleedingCurrent - blendAmountBleedingRate;
		elseif blendAmountBleedingCurrent <= blendAmountBleedingIdeal then
			blendAmountBleedingCurrent = blendAmountBleedingCurrent + blendAmountBleedingRate;
		end
--Bleeding2 overlay	
		if (BleedingLevel < 2) then
				blendAmountBleeding2Current = 0;	
		end

		--if (BleedingLevel >= 2) then
			--if blendAmountBleeding2Current >= BleedingLevel then	
				--blendAmountBleeding2Current = blendAmountBleeding2Current - blendAmountBleeding2Rate;

			--elseif blendAmountBleeding2Current < BleedingLevel then
				--blendAmountBleeding2Current = blendAmountBleeding2Current + blendAmountBleeding2Rate;
			--end

		if (BleedingLevel >= 2) then		
			--This block sets our ideal states
			if blendAmountBleeding2Current > blendAmountBleeding2Upper then			
				blendAmountBleeding2Ideal = blendAmountBleeding2Lower;
			
			elseif blendAmountBleeding2Current < blendAmountBleeding2Lower then
				blendAmountBleeding2Ideal = blendAmountBleeding2Upper;						
			end
		else
			if blendAmountBleeding2Current > 0 then
				blendAmountBleeding2Current = blendAmountBleeding2Current - blendAmountBleeding2Rate;
			end
			if blendAmountBleeding2Current <= 0 then
				blendAmountBleeding2Current = 0;
			end
		end

		if blendAmountBleeding2Current >= blendAmountBleeding2Ideal then	
			blendAmountBleeding2Current = blendAmountBleeding2Current - blendAmountBleeding2Rate;
		elseif blendAmountBleeding2Current <= blendAmountBleeding2Ideal then
			blendAmountBleeding2Current = blendAmountBleeding2Current + blendAmountBleeding2Rate;
		end

--Bleeding3 overlay	
		if (BleedingLevel < 3) then
				blendAmountBleeding3Current = 0;	
		end

		--if (BleedingLevel >= 3) then
			--if blendAmountBleeding3Current >= BleedingLevel then	
				--blendAmountBleeding3Current = blendAmountBleeding3Current - blendAmountBleeding3Rate;

			--elseif blendAmountBleeding3Current < BleedingLevel then
				--blendAmountBleeding3Current = blendAmountBleeding3Current + blendAmountBleeding3Rate;
			--end

		if (BleedingLevel >= 3) then		
			--This block sets our ideal states
			if blendAmountBleeding3Current > blendAmountBleeding3Upper then			
				blendAmountBleeding3Ideal = blendAmountBleeding3Lower;
			
			elseif blendAmountBleeding3Current < blendAmountBleeding3Lower then
				blendAmountBleeding3Ideal = blendAmountBleeding3Upper;						
			end

		else
			if blendAmountBleeding3Current > 0 then
				blendAmountBleeding3Current = blendAmountBleeding3Current - blendAmountBleeding3Rate;
			end
			if blendAmountBleeding3Current <= 0 then
				blendAmountBleeding3Current = 0;
			end
		end

		if blendAmountBleeding3Current >= blendAmountBleeding3Ideal then	
			blendAmountBleeding3Current = blendAmountBleeding3Current - blendAmountBleeding3Rate;
		elseif blendAmountBleeding3Current <= blendAmountBleeding3Ideal then
			blendAmountBleeding3Current = blendAmountBleeding3Current + blendAmountBleeding3Rate;
		end

--Zombie overlay (sine pulse — slow and ominous, speeds up with infection level)
		if ZombieLevel < 1 then
			blendAmountZombieCurrent = 0;
		else
			local speed     = 0.3 + ZombieLevel * 0.15;
			local peakAlpha = 0.08 + (ZombieLevel - 1) * 0.12;
			blendAmountZombieCurrent = (math.sin(os.clock() * speed * math.pi) * 0.5 + 0.5) * peakAlpha * blendCapZombie;
		end


		--Draw order block. DO NOT FORGET TO ADD OVERLAY HERE:
		--BOTTOM 

--print("Overlays: Wet: " .. blendAmountWetCurrent);
		if blendAmountWetCurrent > 0 then
		UIManager.DrawTexture( overlayWet, 0, 0, screenX, screenY, (blendAmountWetCurrent / blendCapWet))
		end
--print("Overlays: Wet2: " .. blendAmountWet2Current);
		if blendAmountWet2Current > 0 then
		UIManager.DrawTexture( overlayWet2, 0, 0, screenX, screenY, (blendAmountWet2Current / blendCapWet2))
		end
--print("Overlays: Wet3: " .. blendAmountWet3Current);
		if blendAmountWet3Current > 0 then
		UIManager.DrawTexture( overlayWet3, 0, 0, screenX, screenY, (blendAmountWet3Current / blendCapWet3))
		end

--print("Overlays: Bleeding: " .. blendAmountBleedingCurrent);
		if blendAmountBleedingCurrent > 0 then
		UIManager.DrawTexture( overlayBleeding, 0, 0, screenX, screenY, (blendAmountBleedingCurrent / blendCapBleeding))
		end
--print("Overlays: Bleeding2: " .. blendAmountBleeding2Current);
		if blendAmountBleeding2Current > 0 then
		UIManager.DrawTexture( overlayBleeding2, 0, 0, screenX, screenY, (blendAmountBleeding2Current / blendCapBleeding2))
		end
--print("Overlays: Bleeding3: " .. blendAmountBleeding3Current);
		if blendAmountBleeding3Current > 0 then
		UIManager.DrawTexture( overlayBleeding3, 0, 0, screenX, screenY, (blendAmountBleeding3Current / blendCapBleeding3))
		end

--print("Overlays: Zombie: " .. blendAmountZombieCurrent);
		if blendAmountZombieCurrent > 0 then
		UIManager.DrawTexture( overlayZombie, 0, 0, screenX, screenY, (blendAmountZombieCurrent / blendCapZombie))
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