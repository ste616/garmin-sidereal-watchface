using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;
using Toybox.Application;
using Toybox.Time.Gregorian;
using Toybox.Time;
using Toybox.ActivityMonitor;

class GarminSiderealWatchfaceView extends WatchUi.WatchFace {

	// Some parameters to control how the watch face looks.
    static const HOUR_TICK_LENGTH = 10;
    static const NEW_MOON_JD = 2451550.1d;
	static const JULIAN_DAY_J2000 = 2451545.0d;
	static const JULIAN_DAYS_IN_CENTURY = 36525.0d;
	static const SOLAR_TO_SIDEREAL = 1.002737909350795d;
	static const MJD_REFERENCE = 2400000.5d;
	static const MOON_PHASE_PERIOD = 29.530588853d;
	static const MOON_SIDE_LEFT = 1;
	static const MOON_SIDE_RIGHT = 2;
	static const MOON_ILLUMINATION_INSIDE = 3;
	static const MOON_ILLUMINATION_OUTSIDE = 4;
	static const ELEVATION_TYPE_LOW = 5;
	static const ELEVATION_TYPE_HIGH = 6;

	var ZERO_RADIANS;
	var middleX;
	var middleY;
	var thirdX;
	var thirdY;
	var quarterX;
	var quarterY;
	var arcRadius;
	var fullRadius;
	var arcExtra;
	var sunRadius;
	var SIDEREAL_HAND_LENGTH;

	// All the colours we have for the elements.
	var backgroundColour;
	var lstTicksColour;
	var localTimeColour;
	var utcTimeColour;
	var lstHandColour;
	var stepsColour;
	var arcColoursLow;
	var arcColoursHigh;
	var moonColour;
	var moonInverted;
	var segmentColours;
	var okBatteryColour;
	var lowBatteryColour;

    function initialize() {
        WatchFace.initialize();
        // Get the size of the screen.
        var deviceSettings = System.getDeviceSettings();

        // Calculate the halfs, thirds and quarters.
		middleX = deviceSettings.screenWidth / 2;
		middleY = deviceSettings.screenHeight / 2;
		thirdX = deviceSettings.screenWidth / 3;
		thirdY = deviceSettings.screenHeight / 3;
		quarterX = deviceSettings.screenWidth / 4;
		quarterY = deviceSettings.screenHeight / 4;

		// The radius of the clock markings.
		arcRadius = deviceSettings.screenHeight / 2.3;

		// Now the radii of the three LST range segments.
		sunRadius = (deviceSettings.screenHeight / 2.0) - 3;
		fullRadius = deviceSettings.screenHeight / 2.0;

		arcExtra = fullRadius - (arcRadius - 1.5 * HOUR_TICK_LENGTH);

		// The length of the sidereal hand.
		SIDEREAL_HAND_LENGTH = sunRadius * 0.95;
		
		ZERO_RADIANS = -1.0d * Math.PI / 2.0d;
		
    }

    // Load your resources here
    function onLayout(dc) {
        setLayout(Rez.Layouts.WatchFace(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
    }

	// Some storage for the parameters which only need to be computed once.
	var storage_dialHASetsLow = [];
	var storage_dialHASetsHigh = [];
	// Some storage for the parameters which may change for loop to loop.
	var old_location = [0.0d, 0.0d];

    // Update the view.
    function onUpdate(dc) {
    	// Determine which colours to use.
    	decideColours();
    
    	// Get the current time, both local and UTC.
        var utcTime = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        var clockTime = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    
    	// Calculate the MJD.
        var mjd = utcToMjd(utcTime);

		// Work out where we should calculate the LST for.
    	var loc = earthLocation("atca");
    	var locationChanged = false;
    	var locDist = computeDistance(loc, old_location);
    	if (locDist > 1) {
    		locationChanged = true;
    	}
    	old_location = loc;
        
        // Calculate the sidereal time.
        var lst = mjdToLst(mjd, (loc[1].toDouble() / 360.0d), 0.0d);

        // Format the time into a string.
        var timeStringLocal = formatTime(clockTime);
        var timeStringUTC = formatTime(utcTime);
        var dateStringLocal = formatDate(clockTime);
        var doyString = formatDOY();
        var mjdString = formatMJD();

		// The three sources we show arcs for.
		var dialSources = [ calculateSunPosition(mjd),
							[ rightAscensionRadians([ 19, 39, 25.026 ]), declinationRadians([ -1, 63, 42, 45.63 ]) ],
							[ rightAscensionRadians([ 8, 25, 26.869 ]), declinationRadians([ -1, 50, 10, 38.49 ]) ] ];
		var dialChanges = [ true, false, false ];
		var lowElevation = [ -18.0d, 12.0d, 12.0d ];
		var highElevation = [ 0.0d, 30.0d, 30.0d ];
		// Calculate the HA sets for these sources.
		var dialHASetsLow = [];
		var dialHASetsHigh = [];
		var i;
		for (i = 0; i < dialSources.size(); i++) {
			if ((dialChanges[i] == true) || (locationChanged == true) || (storage_dialHASetsLow.size() <= i)) {
				dialHASetsLow.add(haset_azel(dialSources[i][1], loc[0], lowElevation[i]));
				dialHASetsHigh.add(haset_azel(dialSources[i][1], loc[0], highElevation[i]));
			} else {
				dialHASetsLow.add(storage_dialHASetsLow[i]);
				dialHASetsHigh.add(storage_dialHASetsHigh[i]);
			}
			if (storage_dialHASetsLow.size() <= i) {
				storage_dialHASetsLow.add(dialHASetsLow[i]);
				storage_dialHASetsHigh.add(dialHASetsHigh[i]);
			} else {
				storage_dialHASetsLow[i] = dialHASetsLow[i];
				storage_dialHASetsHigh[i] = dialHASetsHigh[i];
			}
		}
		
		// Calculate the current moon phase and illumination.
		var moonPhase = calculateMoonPhase(mjd);
		var moonIllumination = calculateMoonIllumination(moonPhase);

        // Update the view.
		dc.setColor( Graphics.COLOR_TRANSPARENT, backgroundColour );
		dc.clear();
		
		drawMoonIllumination(dc, moonIllumination);

		// Draw the 24 hours of the sidereal clock dial.
		drawSiderealDial(dc);
		// Draw the source arcs.
		for (i = 0; i < dialSources.size(); i++) {
			drawVisibilitySegment(dc, dialSources[i][0], dialHASetsLow[i], i, ELEVATION_TYPE_LOW);
			drawVisibilitySegment(dc, dialSources[i][0], dialHASetsHigh[i], i, ELEVATION_TYPE_HIGH);
		}
		// And draw the LST hand.
		drawLSTHand(dc, lst);

		// Get the number of steps.
		var info = ActivityMonitor.getInfo();
		var steps = info.steps;
		
		// Get the battery level.
		var watchStats = System.getSystemStats();
		var batteryString = watchStats.battery.format("%3d") + "%";
		var batteryColour = okBatteryColour;
		if (watchStats.battery <= 20) {
			batteryColour = lowBatteryColour;
		}

		// Draw the text stuff.
		drawFaceText(dc, timeStringLocal, timeStringUTC, dateStringLocal, 
					 doyString, mjdString, steps, batteryString, batteryColour);
		
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() {
    }

    // Terminate any active timers and prepare for slow updates.
    function onEnterSleep() {
    }

	// Our functions.
	// Set the colours based on the background colour setting.
	function decideColours() {
		// Get the value of the background colour.
		backgroundColour = Application.Properties.getValue("BackgroundColor");
		if (backgroundColour == Graphics.COLOR_BLACK) {
			// Black background.
			System.println("black background settings");
			lstTicksColour = Graphics.COLOR_BLUE;
			moonColour = Graphics.COLOR_DK_GRAY;
			moonInverted = false;
			localTimeColour = Graphics.COLOR_WHITE;
			utcTimeColour = Graphics.COLOR_BLUE;
			stepsColour = Graphics.COLOR_RED;
			segmentColours = [ [ Graphics.COLOR_ORANGE, Graphics.COLOR_YELLOW ],
							   [ Graphics.COLOR_DK_GREEN, Graphics.COLOR_GREEN ],
							   [ Graphics.COLOR_PURPLE, Graphics.COLOR_PINK ] ];
			lstHandColour = Graphics.COLOR_RED;
			okBatteryColour = Graphics.COLOR_GREEN;
			lowBatteryColour = Graphics.COLOR_RED;
		} else if (backgroundColour == Graphics.COLOR_WHITE) {
			// White background.
			System.println("white background settings");
			lstTicksColour = Graphics.COLOR_DK_BLUE;
			moonColour = Graphics.COLOR_LT_GRAY;
			moonInverted = true;
			localTimeColour = Graphics.COLOR_BLACK;
			utcTimeColour = Graphics.COLOR_DK_BLUE;
			stepsColour = Graphics.COLOR_RED;
			segmentColours = [ [ Graphics.COLOR_ORANGE, Graphics.COLOR_YELLOW ],
							   [ Graphics.COLOR_DK_GREEN, Graphics.COLOR_GREEN ],
							   [ Graphics.COLOR_PURPLE, Graphics.COLOR_PINK ] ];
			lstHandColour = Graphics.COLOR_DK_RED;
			okBatteryColour = Graphics.COLOR_DK_GREEN;
			lowBatteryColour = Graphics.COLOR_DK_RED;
		}
	}
	
	// Calculate the distance between two locations.
	function computeDistance(loc1, loc2) {
		var dist = Math.sqrt(Math.pow((loc2[0] - loc1[0]), 2) + Math.pow((loc2[1] - loc1[1]), 2));
		// The distance is in degrees.
		return dist;
	}
	
	// Turn HMS into a day fraction.
	function timeToTurns(utcTime) {
		var turns = ((utcTime.sec.toDouble()) + (utcTime.min.toDouble() * 60.0d) + (utcTime.hour.toDouble() * 3600.0d)) / 86400.0d;
		return(turns);
	}
	
	// Calculate the Julian day.
	// We don't do the full calculation every time, and we store the base MJD here.
	var baseMjd = 0.0d;
	// We only recalculate the base MJD if the UTC fraction is less than it was previously.
	// We set it to 2 at the start so we always recalculate the first time.
	var priorUtc = 2.0d;
	// We also calculate the MJD at the start of the year during the first run.
	var yearBaseMjd = 0.0d;
	// And when we see the year change.
	var priorYear = 0;
	function utcToMjd(utcTime) {
		// Turn the UTC HMS into a fraction of a day.
		var utc = timeToTurns(utcTime);
		// Check if we have changed day.
		var dayChanged = false;
		if ((utc < priorUtc) || (baseMjd == 0)) {
			dayChanged = true;
		}
		priorUtc = utc;
		// Check if we have changed year.
		var yearChanged = false;
		if ((utcTime.year > priorYear) || (yearBaseMjd == 0)) {
			yearChanged = true;
		}
		priorYear = utcTime.year;
		if (dayChanged == true) {
			// Calculate the base MJD.
			baseMjd = calculateBaseMjd([ utcTime.year, utcTime.month, utcTime.day ]);
		}
		if (yearChanged == true) {
			// Calculate the MJD on the first day of the year.
			yearBaseMjd = calculateBaseMjd([ utcTime.year, 1, 1 ]);
		}
		return (baseMjd + utc);
	}

	function calculateBaseMjd(utcArray) {
		var m = (utcArray[1] - 3).toDouble();
		var y = utcArray[0].toDouble();
		if (utcArray[1] <= 2) {
			m = (utcArray[1] + 9).toDouble();
			y = (utcArray[0] - 1).toDouble();
		}
		var c = (y / 100.0d).toNumber().toDouble();
		y -= c * 100.0d;
		var x1 = (146097.0d * c / 4.0d).toNumber().toDouble();
		var x2 = (1461.0d * y / 4.0d).toNumber().toDouble();
		var x3 = ((153.0d * m + 2.0d) / 5.0d).toNumber().toDouble();
		var mjd = (x1 + x2 + x3 + utcArray[2].toDouble() - 678882.0d);
		return (mjd);
	}
	
	// Calculate the current day of year.
	function calculateDayOfYear() {
		return (baseMjd - yearBaseMjd + 1);
	}

	// Routine to get the location to calculate the LST for.
	function earthLocation(locationName) {
		var loc = [ 0.0, 0.0 ];
		if (locationName.equals("atca")) {
			// Send back the location of the Australia Telescope Compact Array.
			loc[0] = -30.3128846d;
			loc[1] = 149.5501388d;
		} else {
			// Send back the location of the watch.
   			var act = Activity.getActivityInfo().currentLocation;
	    	if (act == null) {
    			System.println("no permission for location");
    		} else {
    			loc = act.toDegrees();
    		}				
		}
		return loc;
	}
	
	// Given any number n, put it between 0 and some other number b.
	function numberBounds(n, b) {
		while (n > b) {
			n -= b;
		}
		while (n < 0.0d) {
			n += b;
		}
		return (n);
	}

	// Given any number, put it between 0 and 1.
	function turnFraction(f) {
		return numberBounds(f, 1.0d);
	}

	// Given any number, put it between 0 and 360.
	function degreesBounds(d) {
		return numberBounds(d, 360.0d);
	}
	
	// Given any number, put it between 0 and 2 PI.
	function radiansBounds(r) {
		return numberBounds(r, (Math.PI * 2.0d));
	}

	// Convert degrees to radians.
	function degreesToRadians(deg) {
		return (deg.toDouble() * Math.PI / 180.0d);
	}
	
	// Convert radians to degrees.
	function radiansToDegrees(rad) {
		return (rad.toDouble() * 180.0d / Math.PI);
	}
	
	// Convert an RA [ h, m, s ] to a radian decimal.
	function rightAscensionRadians(ra) {
		var raDecimal = 15.0 * (ra[0].toDouble() + ra[1].toDouble() / 60.0d + ra[2].toDouble() / 3600.0d);
		return degreesToRadians(raDecimal);
	}
	
	// Convert a Declination [ sign, d, m, s ] to a radian decimal.
	function declinationRadians(dec) {
		var decDecimal = dec[0].toDouble() * (dec[1].toDouble() + dec[2].toDouble() / 60.0d + 
											  dec[3].toDouble() / 3600.0d);
		return degreesToRadians(decDecimal);
	}
	
	// Calculate the sidereal time at Greenwich, given an MJD.
	function gst(mjd, dUT1) {
		if ((dUT1 > 0.5d) || (dUT1 < -0.5d)) {
			System.println("dUT1 is out of range at " + dUT1.format("%.4f"));
			return 0.0d;
		}
		
		var a = 101.0d + 24110.54581d / 86400.0d;
		var b = 8640184.812866d / 86400.0d;
		var e = 0.093104d / 86400.0d;
		var d = 0.0000062d / 86400.0d;
		var tu = (mjd.toNumber().toDouble() - (JULIAN_DAY_J2000 - MJD_REFERENCE)) / JULIAN_DAYS_IN_CENTURY;
		var sidtim = turnFraction(a + tu * (b + tu * (e - tu * d)));
		var gmst = turnFraction(sidtim + (mjd - mjd.toNumber().toDouble() + dUT1 / 86400.0d) * SOLAR_TO_SIDEREAL);
		
		return gmst;
	}

	// Calculate the sidereal time at some longitude on the Earth.
	function mjdToLst(mjd, longitude, dUT1) {
		var lst = turnFraction(gst(mjd, dUT1) + longitude);
		
		return lst;
	}

	// Calculate and return the Right Ascension and Declination of the Sun
	// at the supplied MJD.
	// The previous MJD for the Sun calculation.
	var priorSunMjd = 0.0d;
	// The Sun's location.
	var solRaDec = [ 0.0d, 0.0d ];
	function calculateSunPosition(mjd) {
		// Check if we need to calculate the Sun's position.
		var calcRequired = false;
		if (mjd > (priorSunMjd + 0.5d)) {
			// Calculate the Sun's position every half-day.
			calcRequired = true;
		}
		if (calcRequired == true) {
			priorSunMjd = mjd;
			solRaDec = sunPosition(mjd);
		}
		return solRaDec;
	}
	
	function sunPosition(mjd) {
		// Get the number of days since 0 UTC Jan 1 2000.
		var jd = mjd + MJD_REFERENCE;
		var n = jd - JULIAN_DAY_J2000;
		// The longitude of the Sun, in degrees.
		var L = 280.460d + 0.9856474d * n;
		// Mean anomaly of the Sun, in degrees.
		var g = 357.528d + 0.9856003d * n;
		// Ensure bound limits for these numbers.
		L = degreesBounds(L);
		g = degreesBounds(g);
		// Ecliptic longitude of the Sun, in degrees.
		var lambda = L + 1.915d * Math.sin(degreesToRadians(g)) + 0.020d * Math.sin(2.0d * degreesToRadians(g));
		// Sun distance from Earth.
		var R = 1.00014d - 0.01671 * Math.cos(degreesToRadians(g)) - 0.00014d * Math.cos(2.0d * degreesToRadians(g));
		// The obliquity, in degrees.
		// We need the number of centuries since J2000.0.
		var T = (n / (100.0d * 365.2525d));
		var epsilon = 23.4392911d - (46.636769d / 3600.0d) * T - (0.0001831d / 3600.0d) * T * T + (0.00200340d / 3600.0d) * T * T * T;
		// Get the right ascension, in radians. We have to shift it by Pi because the
		// atan2 range is -Pi -> Pi.
		var alpha = Math.atan2(Math.cos(degreesToRadians(epsilon)) * Math.sin(degreesToRadians(lambda)), Math.cos(degreesToRadians(lambda)));
		// And declination, in radians.
		var delta = Math.asin(Math.sin(degreesToRadians(epsilon)) * Math.sin(degreesToRadians(lambda)));
		//System.println("Sun alpha = " + alpha.format("%.5f") + " delta = " + delta.format("%.5f"));
		return ([ alpha, delta ]);
	}
	
	// Calculate the Moon phase.
	var priorMoonMjd = 0.0d;
	// The Moon's phase.
	var lunPhase = [ 0.0d, 0.0d ];
	function calculateMoonPhase(mjd) {
		// Check if we need to calculate the Moon's phase.
		var calcRequired = false;
		if (mjd > (priorMoonMjd + 0.25d)) {
			// Calculate the Sun's position every quarter-day.
			calcRequired = true;
		}
		if (calcRequired == true) {
			// Get the number of days since the new moon reference.
			var n = mjd + MJD_REFERENCE - NEW_MOON_JD;
			// How many new moons is that?
			var numNewMoons = n / MOON_PHASE_PERIOD;
			// We only care about the fractional bit.
			priorMoonMjd = mjd;
			lunPhase = turnFraction(numNewMoons);
		}
		return (lunPhase);
	}
	
	// Calculate the Moon illumination.
	function calculateMoonIllumination(moonPhase) {
		// If the phase is below 0.5 it's waxing, waning above it.
		var illum = 1.0d - (moonPhase * 2.0d - 1.0d).abs();
		return (illum * ((moonPhase < 0.5) ? -1.0d : 1.0d));
	}

	// Calculate the hour angle for a rise or set of a source with specified
	// declination, from a position with specified latitude. The rise/set elevation
	// must also be specified.
	function haset_azel(dec, lat, lowElev) {
		var cos_haset = (Math.cos(Math.PI / 2.0d - degreesToRadians(lowElev)) - Math.sin(degreesToRadians(lat)) * Math.sin(dec)) / (Math.cos(dec) * Math.cos(degreesToRadians(lat)));
		if (cos_haset > 1.0d) {
			// The source never rises.
			return 0.0d;
		}
		if (cos_haset < -1.0d) {
			// The source never sets.
			return (Math.PI);
		}
		// Return the HA, in radians.
		//return (Math.acos(cos_haset) * 24.0d / (Math.PI * 2.0d));
		return (Math.acos(cos_haset));
	}
	
	// Format a time object into a string for the watch face.
	function formatTime(timeObj) {
        var timeFormat = "$1$:$2$";
        var timeString = Lang.format(timeFormat, [timeObj.hour.format("%02d"), 
        	timeObj.min.format("%02d")]);
		return (timeString);
	}
	
	// Format a time object into a date string.
	function formatDate(timeObj) {
		var dateFormat = "$1$ $2$-$3$-$4$";
		var dateString = Lang.format(dateFormat,
			[ dayName(timeObj.day_of_week), timeObj.year.format("%04d"), 
			  timeObj.month.format("%02d"), timeObj.day.format("%02d") ]);
		return (dateString);
	}
	
	// Format a time into a DOY string.
	function formatDOY() {
		var doyFormat = "$1$ ";
		var doyString = Lang.format(doyFormat, [ calculateDayOfYear().format("%03d") ] );
		return (doyString);
	}
	
	// Format the MJD into a string.
	function formatMJD() {
		var mjdFormat = "$1$";
		var mjdString = Lang.format(mjdFormat, [ baseMjd.format("%5d") ] );
		return (mjdString);
	}
	
	// Return the name of the day.
	function dayName(dayNumber) {
		switch (dayNumber) {
		case Gregorian.DAY_SUNDAY:
			return "Sun";
		case Gregorian.DAY_MONDAY:
			return "Mon";
		case Gregorian.DAY_TUESDAY:
			return "Tue";
		case Gregorian.DAY_WEDNESDAY:
			return "Wed";
		case Gregorian.DAY_THURSDAY:
			return "Thu";
		case Gregorian.DAY_FRIDAY:
			return "Fri";
		case Gregorian.DAY_SATURDAY:
			return "Sat";	
		}
		return "Wat";
	}

	// Work out a line segment that emits radially from the centre to the edge.
    function calcLineFromCircleEdge(arcRadius, lineLength, radian) {
        var pointX = ((arcRadius-lineLength) * Math.cos(radian)).toNumber()+middleX;
        var endX = (arcRadius * Math.cos(radian)).toNumber()+middleX;
        var pointY = ((arcRadius-lineLength) * Math.sin(radian)).toNumber()+middleY;
        var endY = (arcRadius * Math.sin(radian)).toNumber()+middleY;
        return [pointX,pointY,endX,endY];
    }


	// Draw the sidereal dial.
	function drawSiderealDial(dc) {
		var points = calcLineFromCircleEdge(arcRadius - 1.1 * HOUR_TICK_LENGTH, HOUR_TICK_LENGTH / 2.0, ZERO_RADIANS);
		dc.setColor(lstTicksColour, Graphics.COLOR_TRANSPARENT);
		dc.setPenWidth(7);
		dc.drawLine(points[0], points[1], points[2], points[3]);
		for (var i = 0; i < 24; i++) {
			var dayFrac = i.toDouble() / 24.0d;
			var radian = ZERO_RADIANS + dayFrac * Math.PI * 2.0d;
			// Draw the hour tick.
			if (i > 0) {
				points = calcLineFromCircleEdge(arcRadius - 1.1 * HOUR_TICK_LENGTH, HOUR_TICK_LENGTH / 4.0, radian);
				dc.setPenWidth(5);
				dc.drawLine(points[0], points[1], points[2], points[3]);
			}
			// Draw the 20 minute ticks.
			for (var j = 1; j < 3; j++) {
				dayFrac += 1.0d / (24.0d * 3.0d);
				radian = ZERO_RADIANS + dayFrac * Math.PI * 2.0d;
				points = calcLineFromCircleEdge(arcRadius - 1.1 * HOUR_TICK_LENGTH, HOUR_TICK_LENGTH / 4.0, radian);
				dc.setPenWidth(2);
				dc.drawLine(points[0], points[1], points[2], points[3]);		
			}
		}
		dc.setPenWidth(1);
	}
	
	// Draw one half of the Moon phase indicator.
	function drawMoonHalf(dc, side, illumination, fraction) {
		// The whole radius of the middle circle.
		var innerRadius = arcRadius - 1.2 * HOUR_TICK_LENGTH;

		// Set the clip.
		if (side == MOON_SIDE_LEFT) {
			dc.setClip((middleX - innerRadius), (middleY - innerRadius), 
				   	   innerRadius + 1, (2 * innerRadius));
		} else if (side == MOON_SIDE_RIGHT) {
			dc.setClip(middleX, (middleY - innerRadius), 
				       innerRadius, (2 * innerRadius));
		}

		// The Moon colour.
		var ellipseColour = moonColour;
		if (moonInverted) {
			ellipseColour = backgroundColour;
		}
		var xRadius = innerRadius;
		if (illumination == MOON_ILLUMINATION_INSIDE) {
			// We only illuminate only part of the half.
			xRadius = fraction * innerRadius;
		} else if (illumination == MOON_ILLUMINATION_OUTSIDE) {
			// That means we first illuminate the whole half, then deilluminate the middle bit.
			dc.setColor(moonColour, Graphics.COLOR_TRANSPARENT);
			if (moonInverted) {
				dc.setColor(backgroundColour, Graphics.COLOR_TRANSPARENT);
			}
			dc.fillCircle(middleX, middleY, innerRadius);
			ellipseColour = backgroundColour;
			if (moonInverted) {
				ellipseColour = moonColour;
			}
			// The illumination is low, so the radius is from what's left.
			xRadius = (1.0d - fraction) * innerRadius;
		}
		if (xRadius > 0) {
			dc.setColor(ellipseColour, Graphics.COLOR_TRANSPARENT);
			dc.fillEllipse(middleX, middleY, xRadius, innerRadius); 
		} else if (moonInverted) {
			// We have to draw non-illuminated sides too.
			dc.setColor(moonColour, Graphics.COLOR_TRANSPARENT);
			dc.fillCircle(middleX, middleY, innerRadius);
		}	
			
		// Reset the clip.
		dc.clearClip();
	}
	
	// Draw the moon phase indicator.
	function drawMoonIllumination(dc, moonIllumination) {
		// We draw the background behind the centre part of the dial.
		// We split it into two halves. The two halves can have different illuminations.
		var rightHalf = 0.0d;
		var leftHalf = 0.0d;
		var waxing = false;
		var leftMode = -1;
		var rightMode = -1;
		if (moonIllumination < 0) {
			// Waxing.
			waxing = true;
			rightMode = MOON_ILLUMINATION_OUTSIDE;
			leftMode = MOON_ILLUMINATION_INSIDE;
			if (moonIllumination.abs() < 0.5) {
				rightHalf = 2.0d * moonIllumination.abs();
			} else {
				rightHalf = 1.0d;
				leftHalf = (moonIllumination.abs() - 0.5d) * 2.0d;
			}
		} else {
			// Waning.
			rightMode = MOON_ILLUMINATION_INSIDE;
			leftMode = MOON_ILLUMINATION_OUTSIDE;
			if (moonIllumination < 0.5) {
				leftHalf = 2.0d * moonIllumination;
			} else {
				leftHalf = 1.0d;
				rightHalf = (moonIllumination - 0.5d) * 2.0d;
			}
		}

		// Use our drawing routine now.
		drawMoonHalf(dc, MOON_SIDE_LEFT, leftMode, leftHalf);
		drawMoonHalf(dc, MOON_SIDE_RIGHT, rightMode, rightHalf);
	}
	
	// Draw a source visibility segment.
	function drawVisibilitySegment(dc, rightAscension, haRange, sourceNumber, elevationType) {
		// Calculate the source rise and set radians.
		var sourceRiseDegrees = degreesBounds(360.0 - radiansToDegrees(rightAscension - haRange) + 90.0);
		var sourceSetDegrees = degreesBounds(360.0 - radiansToDegrees(rightAscension + haRange) + 90.0);
		
		// Set the colour based on the source number.
		var arcColour = segmentColours[sourceNumber][0];
		if (elevationType == ELEVATION_TYPE_HIGH) {
			arcColour = segmentColours[sourceNumber][1];
		}
		dc.setColor(arcColour, Graphics.COLOR_TRANSPARENT);
		dc.setPenWidth(10);
		
		// Set the radius of the arc based on the source number.
		var arcRadius = sunRadius;
		if (sourceNumber > 0) {
			arcRadius = fullRadius - (sourceNumber.toDouble() * arcExtra / 3.0d);
		}

		// Draw the arc now.
		dc.drawArc(middleX, middleY, arcRadius, Graphics.ARC_CLOCKWISE, sourceRiseDegrees, sourceSetDegrees);
		
	}
	
	// Draw the LST hand.
	function drawLSTHand(dc, lst) {
		var points = calcLineFromCircleEdge(fullRadius, arcExtra, ZERO_RADIANS + (lst * 2.0d * Math.PI));
		dc.setColor(lstHandColour, Graphics.COLOR_TRANSPARENT);
		dc.setPenWidth(3);
		dc.drawLine(points[0], points[1], points[2], points[3]);
		dc.setPenWidth(1); 
	}

	// Draw all the text elements on the face.
	function drawFaceText(dc, localTimeString, utcTimeString, dateString, doyString, 
						  mjdString, numSteps, batteryString, batteryColour) {
		// Draw the local text string.
		var localText = new WatchUi.Text({
			:text=>localTimeString, :color=>localTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>thirdX, :locY=>thirdY });
		localText.draw(dc);
		// Make the "LOC" label.
		var localLabel = new WatchUi.Text({
			:text=>"LOC", :color=>localTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_RIGHT,
			:font=>Graphics.FONT_XTINY, :locX=>(thirdX + (localText.width / 2)),
			:locY=>(thirdY - localText.height) });
		localLabel.draw(dc);
		
		// Draw the UTC text string.
		var utcText = new WatchUi.Text({
			:text=>utcTimeString, :color=>utcTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>(2 * thirdX), :locY=>thirdY });
		utcText.draw(dc);
		// Make the "UTC" label.
		var utcLabel = new WatchUi.Text({
			:text=>"UTC", :color=>utcTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_XTINY, :locX=>((2 * thirdX) - (utcText.width / 2)),
			:locY=>(thirdY - utcText.height) });
		utcLabel.draw(dc);
		
		// Put the battery level on the top.
		var batteryText = new WatchUi.Text({
			:text=>batteryString, :color=>batteryColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_XTINY, :locX=>middleX,
			:locY=>(utcLabel.locY - 0.7 * utcLabel.height) });
		batteryText.draw(dc);
		
		// Draw the local date.
		var dateText = new WatchUi.Text({
			:text=>dateString, :color=>localTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_SMALL, :locX=>middleX,
			:locY=>(thirdX + localText.height) });
		dateText.draw(dc);
		
		// Draw the DOY.
		var doyLineY = thirdX + localText.height + (0.95 * dateText.height);
		var doyText = new WatchUi.Text({
			:text=>doyString, :color=>localTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>(thirdX - (localText.width / 2.0)),
			:locY=>doyLineY });
		doyText.draw(dc);
		// And the label.
		var doyLabel = new WatchUi.Text({
			:text=>"D", :color=>localTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_SYSTEM_XTINY, :locX=>(doyText.locX + (0.9 * doyText.width)),
			:locY=>(doyLineY - (0.23 * doyText.height)) });
		doyLabel.draw(dc); 
		
		// Draw the MJD.
		var mjdText = new WatchUi.Text({
			:text=>mjdString, :color=>utcTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>middleX,
			:locY=>doyLineY });
		mjdText.draw(dc);
		var mjdLabel = new WatchUi.Text({
			:text=>"J ", :color=>utcTimeColour,
			:justification=>Graphics.TEXT_JUSTIFY_RIGHT,
			:font=>Graphics.FONT_SYSTEM_XTINY, :locX=>mjdText.locX,
			:locY=>(doyLineY + (0.2 * doyText.height)) });
		mjdLabel.draw(dc);
		
		// Draw the number of steps.
		var nStepsText = new WatchUi.Text({
			:text=>numSteps.format("%d"), :color=>stepsColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>middleX,
			:locY=>(doyLineY + 1.2 * mjdText.height) });
		nStepsText.draw(dc); 
		var nStepsLabel = new WatchUi.Text({
			:text=>"steps", :color=>stepsColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_XTINY, :locX=>middleX,
			:locY=>(nStepsText.locY + 0.8 * nStepsText.height) });
		nStepsLabel.draw(dc);
	}

}
