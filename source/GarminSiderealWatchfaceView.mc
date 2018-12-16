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
	static const DTOR = 0.017453293d;

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
    	var loc = earthLocation();
    	var locationChanged = false;
    	var locDist = computeDistance(loc, old_location);
    	if (locDist > 1) {
    		locationChanged = true;
    	}
    	old_location = loc;
        
        // Calculate the sidereal time.
        var lst = mjdToLst(mjd, (loc[1].toDouble() / 360.0d), 0.0d);
        moonPosition(mjd);

        // Format the time into a string.
        var timeStringLocal = formatTime(clockTime);
        var timeStringUTC = formatTime(utcTime);
        var dateStringLocal = formatDate(clockTime);
        var doyString = formatDOY();
        var mjdString = formatMJD();

		// The three sources we show arcs for.
		var dialHASets = dialSourceCompute(mjd, loc, locationChanged);
		
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
		for (var i = 0; i < 3; i++) {
			drawVisibilitySegment(dc, dialHASets[2][i][0], dialHASets[0][i], i, ELEVATION_TYPE_LOW);
			drawVisibilitySegment(dc, dialHASets[2][i][0], dialHASets[1][i], i, ELEVATION_TYPE_HIGH);
		}
		// And draw the LST hand.
		drawLSTHand(dc, lst);

		// Get the number of steps.
		var info = ActivityMonitor.getInfo();
		var steps = info.steps;
		
		// Get the battery level.
		var watchStats = System.getSystemStats();
		var topLabelType = Application.Properties.getValue("TopNumberType");
		var batteryString = "";
		if (topLabelType == 0) {
			batteryString = watchStats.battery.format("%3d") + "%";
		} else if (topLabelType == 1) {
			var ml = moonIllumination.abs() * 100.0;
			batteryString = ml.format("%3d") + "%";
		}
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
	static const SIDEREAL_LOCATION_TYPE_GPS = 0;
	static const SIDEREAL_LOCATION_TYPE_NAMED = 1;
	static const SIDEREAL_LOCATION_TYPE_LATLON = 2;
	static const SIDEREAL_LOCATION_NAME_ATCA = 0;
	static const SIDEREAL_LOCATION_NAME_PARKES = 1;
	function earthLocation() {
		var loc = [ 0.0, 0.0 ];
		// Get the watchface setting.
		var locationType = Application.Properties.getValue("SiderealLocationType");
		if (locationType == SIDEREAL_LOCATION_TYPE_GPS) {
			// Send back the location of the watch.
   			var act = Activity.getActivityInfo().currentLocation;
	    	if (act == null) {
    			System.println("no permission for location");
    		} else {
    			loc = act.toDegrees();
    		}				
		} else if (locationType == SIDEREAL_LOCATION_TYPE_NAMED) {
			var locationName = Application.Properties.getValue("LocationName");
			if (locationName == SIDEREAL_LOCATION_NAME_ATCA) {
				// Send back the location of the Australia Telescope Compact Array.
				loc[0] = -30.3128846d;
				loc[1] = 149.5501388d;
			} else if (locationName == SIDEREAL_LOCATION_NAME_PARKES) {
				// The Parkes 64m telescope.
				loc[0] = -32.99840638d;
				loc[1] = 148.26351d;
			}
		} else if (locationType == SIDEREAL_LOCATION_TYPE_LATLON) {
			loc[0] = Application.Properties.getValue("LocationLatitude").toDouble();
			loc[1] = Application.Properties.getValue("LocationLongitude").toDouble();
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

	function FNrange(x) {
		var b = x / (2.0d * Math.PI);
		var p = b.abs().toNumber().toDouble();
		if (b < 0) {
			p *= -1.0d;
		}
		var a = (2.0d * Math.PI) * (b - p);
		if (a < 0) {
			a += (2.0d * Math.PI);
		}
		return a;
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
	
	function polyidl(x, cc) {
		var polysum = 0.0d;
		for (var i = 0; i < cc.size(); i++) {
			polysum += cc[i].toDouble() * Math.pow(x.toDouble(), i.toDouble());
		}
		return (polysum);
	}
	
	function whichabs(v, a) {
		var b = [];
		for (var i = 0; i < a.size(); i++) {
			if (a[i].abs() == v) {
				b.add(i);
			}
		}
		return b;
	}
	
	function multidx(a, b, f) {
		var o = a;
		for (var i = 0; i < b.size(); i++) {
			o[b[i]] *= f;
		}
		return o;
	}
	
	function vec_m_num(v, n) {
		// Multiply a vector by a number.
		for (var i = 0; i < v.size(); i++) {
			v[i] = v[i].toDouble() * n.toDouble();
		}
		return v;
	}
	
	function vec_m_vec(u, v) {
		// Multiply a vector by a vector.
		for (var i = 0; i < u.size(); i++) {
			u[i] = u[i].toDouble() * v[i].toDouble();
		}
		return u;
	}
	
	function vec_a_vec(u, v) {
		// Add one vector to another.
		for (var i = 0; i < u.size(); i++) {
			u[i] = u[i].toDouble() + v[i].toDouble();
		}
		return u;
	}
	
	function vec_sin(v) {
		// Take the sin of a vector.
		for (var i = 0; i < v.size(); i++) {
			v[i] = Math.sin(v[i]);
		}
		return v;
	}
	
	function vec_cos(v) {
		// Take the cos of a vector.
		for (var i = 0; i < v.size(); i++) {
			v[i] = Math.cos(v[i]);
		}
		return v;
	}

	function vec_sum(v) {
		// Sum the vector.
		var s = 0.0d;
		for (var i = 0; i < v.size(); i++) {
			s += v[i].toDouble();
		}
		return s;
	}
	
	function nutate(mjd) {
		var t, coeff1, d, coeff2, m, coeff3, mprime, coeff4, f, coeff5;
		var omega, d_lng, m_lng, mp_lng, f_lng, om_lng, sin_lng, sdelt;
		var cos_lng, cdelt, n, nut_long, nut_obliq, arg, sarg, carg;
		
		t = (mjd + MJD_REFERENCE - JULIAN_DAY_J2000) / JULIAN_DAYS_IN_CENTURY;
		
		coeff1 = [ 297.85036,  445267.111480, -0.0019142, 1.0/189474.0 ];
		d = degreesBounds(polyidl(t, coeff1)) * DTOR;
		coeff2 = [ 357.52772, 35999.050340, -0.0001603, -1.0/3.0e5 ];
		m = degreesBounds(polyidl(t, coeff2)) * DTOR;
		coeff3 = [ 134.96298, 477198.867398, 0.0086972, 1.0/5.625e4 ];
		mprime = degreesBounds(polyidl(t, coeff3)) * DTOR;
		coeff4 = [ 93.27191, 483202.017538, -0.0036825, -1.0/3.27270e5 ];
		f = degreesBounds(polyidl(t, coeff4)) * DTOR;
		coeff5 = [ 125.04452, -1934.136261, 0.0020708, 1.0/4.5e5 ];
		omega = degreesBounds(polyidl(t, coeff5)) * DTOR;
		d_lng = [ 0, -2, 0, 0, 0, 0, -2, 0, 0, -2, -2, -2, 0, 2, 0, 2, 0,
				  0, -2, 0, 2, 0, 0, -2, 0, -2, 0, 0, 2, -2, 0, -2, 0, 0,
				  2, 2, 0, -2, 0, 2, 2, -2, -2, 2, 2, 0, -2, -2, 0, -2, -2,
				  0, -1, -2, 1, 0, 0, -1, 0, 0, 2, 0, 2 ];
		m_lng = [ 0, 0, 0, 0, 1, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
				  0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 2, 1, 0, -1, 0,
				  0, 0, 1, 1, -1, 0, 0, 0, 0, 0, 0, -1, -1, 0, 0, 0, 1, 0,
				  0, 1, 0, 0, 0, -1, 1, -1, -1, 0, -1 ];
		mp_lng = [ 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, -1, 0, 1, -1, -1, 1,
				   2, -2, 0, 2, 2, 1, 0, 0, -1, 0, -1, 0, 0, 1, 0, 2, -1, 1,
				   0, 1, 0, 0, 1, 2, 1, -2, 0, 1, 0, 0, 2, 2, 0, 1, 1, 0, 0,
				   1, -2, 1, 1, 1, -1, 3, 0 ];
		f_lng = [ 0, 2, 2, 0, 0, 0, 2, 2, 2, 2, 0, 2, 2, 0, 0, 2, 0, 2, 0,
				  2, 2, 2, 0, 2, 2, 2, 2, 0, 0, 2, 0, 0, 0, -2, 2, 2, 2, 0,
				  2, 2, 0, 2, 2, 0, 0, 0, 2, 0, 2, 0, 2, -2, 0, 0, 0, 2, 2,
				  0, 0, 2, 2, 2, 2 ];
		om_lng = [ 1, 2, 2, 2, 0, 0, 2, 1, 2, 2, 0, 1, 2, 0, 1, 2, 1, 1, 0,
				   1, 2, 2, 0, 2, 0, 0, 1, 0, 1, 2, 1, 1, 1, 0, 1, 2, 2, 0,
				   2, 1, 0, 2, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 2,
				   0, 0, 2, 2, 2, 2 ];
		sin_lng = [ -171996, -13187, -2274, 2062, 1426, 712, -517, -386, 
					-301, 217, -158, 129, 123, 63, 63, -59, -58, -51, 48, 
					46, -38, -31, 29, 29, 26, -22, 21, 17, 16, -16, -15, 
					-13, -12, 11, -10, -8, 7, -7, -7, -7, 6, 6, 6, -6, -6,
					5, -5, -5, -5, 4, 4, 4, -4, -4, -4, 3, -3, -3, -3, -3,
					-3, -3, -3 ];
		sdelt = [ -174.2, -1.6, -0.2, 0.2, -3.4, 0.1, 1.2, -0.4, 0, -0.5, 
				   0, 0.1, 0, 0, 0.1, 0, -0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
				   0, -0.1, 0, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				   0, 0 ];
		cos_lng = [ 92025, 5736, 977, -895, 54, -7, 224, 200, 129, -95, 0,
				    -70, -53, 0, -33, 26, 32, 27, 0, -24, 16, 13, 0, -12,
				    0, 0, -10, 0, -8, 7, 9, 7, 6, 0, 5, 3, -3, 0, 3, 3,
				    0, -3, -3, 3, 3, 0, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0,
				    0, 0, 0, 0, 0, 0 ];
		cdelt = [ 8.9, -3.1, -0.5, 0.5, -0.1, 0.0, -0.6, 0.0, -0.1, 0.3,
				  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ];
		arg = vec_a_vec(vec_m_num(d_lng, d), vec_m_num(m_lng, m));
		arg = vec_a_vec(arg, vec_m_num(mp_lng, mprime));
		arg = vec_a_vec(arg, vec_m_num(f_lng, f));
		arg = vec_a_vec(arg, vec_m_num(om_lng, omega));
		sarg = vec_sin(arg);
		carg = vec_cos(arg);
		nut_long = 0.0001d * vec_sum(vec_m_vec((vec_a_vec(vec_m_num(sdelt, t), sin_lng)), sarg));
		nut_obliq = 0.0001d * vec_sum(vec_m_vec((vec_a_vec(vec_m_num(cdelt, t), cos_lng)), carg));
		return [ nut_long, nut_obliq ];
	}
	
	// Calculate the Moon location.
	function moonPosition(mjd) {
		var t, ra, dec, d_lng, m_lng, mp_lng, f_lng, sin_lng, cos_lng;
		var d_lat, m_lat, mp_lat, f_lat, sin_lat, coeff0, lprimed, coeff1, d, m;
		var coeff3, coeff4, f, mprime, e, e2, ecorr1, ecorr2, ecorr3, ecorr4;
		var a1, a2, a3, suml_add, sumb_add, geolong, geolat, dis, sinlng;
		var coslng, sinlat, arg, tmp, nlong, elong, lambda, beta, c, epsilon;
		var eps, lprime, coeff2;
		
		t = (mjd + MJD_REFERENCE - JULIAN_DAY_J2000) / JULIAN_DAYS_IN_CENTURY;
		d_lng = [ 0, 2, 2, 0, 0, 0, 2, 2, 2, 2, 0, 1, 0, 2, 0, 0,
				  4, 0, 4, 2, 2, 1, 1, 2, 2, 4, 2, 0, 2, 2, 1, 2,
				  0, 0, 2, 2, 2, 4, 0, 3, 2, 4, 0, 2, 2, 2, 4, 0,
				  4, 1, 2, 0, 1, 3, 4, 2, 0, 1, 2, 2 ];
		m_lng = [ 0, 0, 0, 0, 1, 0, 0, -1, 0, -1, 1, 0, 1, 0, 0, 0,
				  0, 0, 0, 1, 1, 0, 1, -1, 0, 0, 0, 1, 0, -1, 0, 
    			 -2, 1, 2, -2, 0, 0, -1, 0, 0, 1, -1, 2, 2, 1, -1, 0,
    			 0, -1, 0, 1, 0, 1, 0, 0, -1, 2, 1, 0, 0 ];
    	mp_lng = [ 1, -1, 0, 2, 0, 0, -2, -1, 1, 0, -1, 0, 1, 0, 1, 1,
    			  -1, 3, -2, -1, 0, -1, 0, 1, 2, 0, -3, -2, -1, -2, 1,
    			  0, 2, 0, -1, 1, 0, -1, 2, -1, 1, -2, -1, -1, -2, 0,
    			  1, 4, 0, -2, 0, 2, 1, -2, -3, 2, 1, -1, 3,-1 ];
    	f_lng = [ 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, -2, 2, -2, 0,
    			  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0,
    			  -2, 2, 0, 2, 0, 0, 0, 0, 0, 0, -2, 0, 0, 0, 0, -2, -2,
    			  0, 0, 0, 0, 0, 0, 0, -2 ];
    	sin_lng = [ 288774.0d, 1274027.0d, 658314.0d, 213618.0d,
    				-185116.0d, -114332.0d, 58793.0d, 57066.0d,
    				53322.0d, 45758.0d, -40923.0d, -34720.0d,
    				-30383.0d, 15327.0d, -12528.0d, 10980.0d,
    				10675.0d, 10034.0d, 8548.0d, -7888.0d,
    				-6766.0d, -5163.0d, 4987.0d, 4036.0d,
    				3994.0d, 3861.0d, 3665.0d, -2689.0d,
    				-2602.0d, 2390.0d, -2348.0d, 2236.0d, 
    				-2120.0d, -2069.0d, 2048.0d, -1773.0d,
    				-1595.0d, 1215.0d, -1110.0d, -892.0d,
    				-810.0d, 759.0d, -713.0d, -700.0d, 691.0d,
    				596.0d, 549.0d, 537.0d, 520.0d, -487.0d, 
    				-399.0d, -381.0d, 351.0d, -340.0d, 330.0d,
    				327.0d, -323.0d, 299.0d, 294.0d, 0.0d ];
    	cos_lng = [ -20905355.0d, -3699111.0d, -2955968.0d, -569925.0d,
    				48888.0d, -3149.0d, 246158.0d, -152138.0d, 
    				-170733.0d, -204586.0d, -129620.0d, 108743.0d,
    				104755.0d, 10321.0d, 0.0d, 79661.0d, -34782.0d,
    				-23210.0d, -21636.0d, 24208.0d, 30824.0d, -8379.0d,
    				-16675.0d, -12831.0d, -10445.0d, -11650.0d,
    				14403.0d, -7003.0d, 0.0d, 10056.0d, 6322.0d, 
    				-9884.0d,5751.0d, 0.0d, -4950.0d, 4130.0d, 0.0d,
    				-3958.0d, 0.0d, 3258.0d, 2616.0d, -1897.0d, -2117.0d,
    				2354.0d, 0.0d, 0.0d, -1423.0d, -1117.0d, -1571.0d,
    				-1739.0d, 0.0d, -4421.0d, 0.0d, 0.0d, 0.0d, 0.0d,
    				1165.0d, 0.0d, 0.0d, 8752.0d ];
		d_lat = [ 0, 0, 0, 2, 2, 2, 2, 0, 2, 0, 2, 2, 2, 2, 2, 2, 2, 0,
				  4, 0, 0, 0, 1, 0, 0, 0, 1, 0, 4, 4, 0, 4, 2, 2, 2, 2,
				  0, 2, 2, 2, 2, 4, 2, 2, 0, 2, 1, 1, 0, 2, 1, 2, 0, 4,
				  4, 1, 4, 1, 4, 2 ];
		m_lat = [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 1, -1, -1, -1,
				  1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, -1,
				  0, 0, 0, 0, 1, 1, 0, -1, -2, 0, 1, 1, 1, 1, 1, 0, -1,
				  1, 0, -1, 0, 0, 0, -1, -2 ];
		mp_lat = [ 0, 1, 1, 0, -1, -1, 0, 2, 1, 2, 0, -2, 1, 0, -1, 0,
				  -1, -1, -1, 0, 0, -1, 0, 1, 1, 0, 0, 3, 0, -1, 1, -2,
				   0, 2, 1, -2, 3, 2, -3, -1, 0, 0, 1, 0, 1, 1, 0, 0,
				  -2, -1, 1, -2, 2, -2, -1, 1, 1, -1, 0, 0 ];
		f_lat = [ 1, 1, -1, -1, 1, -1, 1, 1, -1, -1, -1, -1, 1, -1, 1, 
				  1, -1, -1, -1, 1, 3, 1, 1, 1, -1, -1, -1, 1, -1, 1,
				 -3, 1, -3, -1, -1, 1, -1, 1, -1, 1, 1, 1, 1, -1, 3, -1,
				 -1, 1, -1, -1, 1, -1, 1, -1, -1, -1, -1, -1, -1, 1 ];
		sin_lat = [ 5128122, 280602, 277693, 173237, 55413, 46271, 
					32573, 17198, 9266, 8822, 8216, 4324, 4200,
					-3359, 2463, 2211, 2065, -1870, 1828, -1794,
					-1749, -1565, -1491, -1475, -1410, -1344,
					-1335, 1107, 1021, 833, 777, 671, 607, 596,
					491, -451, 439, 422, 421, -366, -351, 331, 315,
					302, -283, -229, 223, 223, -220, -220, -185,
					181, -177, 176, 166, -164, 132, -119, 115, 107.0 ];
		coeff0 = [ 218.3164477d, 481267.88123421d, -0.0015786d, 
				   1.0d/538841.0d, -1.0d/6.5194e7d ];
		lprimed = degreesBounds(polyidl(t, coeff0));
		lprime = lprimed * DTOR;
		coeff1 = [ 297.8501921, 445267.1114034, -0.0018819, 1.0/545868.0, 
    			   -1.0/1.13065e8 ];
		d = degreesBounds(polyidl(t, coeff1)) * DTOR;
		coeff2 = [ 357.5291092, 35999.0502909, -0.0001536, 1.0/2.449e7 ];
		m = degreesBounds(polyidl(t, coeff2)) * DTOR;
		coeff3 = [ 134.9633964, 477198.8675055, 0.0087414, 1.0/6.9699e4, 
    			   -1.0/1.4712e7 ];
		mprime = degreesBounds(polyidl(t, coeff3)) * DTOR;
		coeff4 = [ 93.2720950, 483202.0175233, -0.0036539, -1.0/3.526e7, 
    			   1.0/8.6331e8 ];
		f = degreesBounds(polyidl(t, coeff4)) * DTOR;
		e = 1.0d - 0.002516d * t - 7.4e-6d * t * t;
		e2 = e * e;
		ecorr1 = whichabs(1, m_lng);
		ecorr2 = whichabs(1, m_lat);
		ecorr3 = whichabs(2, m_lng);
		ecorr4 = whichabs(2, m_lat);
		a1 = (119.75d + 131.849d * t) * DTOR;
		a2 = (53.09d + 479624.290d * t) * DTOR;
		a3 = (313.45d + 481266.484d * t) * DTOR;
		suml_add = (3958.0d * Math.sin(a1) + 1962.0d * Math.sin(lprime - f) + 
					318.0d * Math.sin(a2));
		sumb_add = (-2235.0d * Math.sin(lprime) + 382.0d * Math.sin(a3) +
					175.0d * Math.sin(a1 - f) + 175.0d * Math.sin(a1 + f) +
					127.0d * Math.sin(lprime - mprime) -
					115.0d * Math.sin(lprime + mprime));
		sinlng = multidx(sin_lng, ecorr1, e);
		coslng = multidx(cos_lng, ecorr1, e);
		sinlat = multidx(sin_lat, ecorr2, e);
		sinlng = multidx(sinlng, ecorr3, e2);
		coslng = multidx(coslng, ecorr3, e2);
		sinlat = multidx(sinlat, ecorr4, e2);
		arg = vec_a_vec(vec_m_num(d_lng, d), vec_m_num(m_lng, m));
		arg = vec_a_vec(arg, vec_m_num(mp_lng, mprime));
		arg = vec_a_vec(arg, vec_m_num(f_lng, f));
		geolong = lprimed + (vec_sum(vec_m_vec(sinlng, vec_sin(arg))) + suml_add) / 1.0e6;
		dis = 385000.56d + vec_sum(vec_m_vec(coslng, vec_cos(arg))) / 1.0e3;
		arg = vec_a_vec(vec_m_num(d_lat, d), vec_m_num(m_lat, m));
		arg = vec_a_vec(arg, vec_m_num(mp_lat, mprime));
		arg = vec_a_vec(arg, vec_m_num(f_lat, f));
		geolat = (vec_sum(vec_m_vec(sinlat, vec_sin(arg))) + sumb_add) / 1.0e6;
		tmp = nutate(mjd);
		nlong = tmp[0];
		elong = tmp[1];
		geolong += degreesBounds(nlong / 3.6e3);
		lambda = geolong * DTOR;
		beta = geolat * DTOR;
		c = [ 21.448, -4680.93, -1.55, 1999.25, -51.38, -249.67,
			 -39.05, 7.12, 27.87, 5.79, 2.45 ];
		epsilon = 23.433333333d + polyidl(t / 1.0e2, c) / 3600.0d;
		eps = (epsilon + elong / 3600.0d) * DTOR;
		ra = Math.atan2(Math.sin(lambda) * Math.cos(eps) -
						Math.tan(beta) * Math.sin(eps), Math.cos(lambda));
		dec = Math.asin(Math.sin(beta) * Math.cos(eps) +
						Math.cos(beta) * Math.sin(eps) * Math.sin(lambda));
		ra /= DTOR;
		dec /= DTOR;
		
		System.print("Moon ra = " + ra.format("%.5f") + "\n");
		System.print("Moon dec = " + dec.format("%.5f") + "\n");
		
	}
	
	// Calculate the Moon phase.
	var priorMoonMjd = 0.0d;
	// The Moon's phase.
	var lunPhase = 0.0d;
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
		if (moonPhase < 0.5) {
			illum *= -1.0d;
		}
		return (illum);
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
	
	// Get the source location settings and return the dial positions.
	// We need some storage to keep values that don't change.
	var storage_dialHASetsLow = [];
	var storage_dialHASetsMid = [];
	var storage_position = [];
	function dialSourceCompute(mjd, loc, locationChanged) {
		// The positions of the sources we show.
		var dialHASets = [ [], [], [] ];
		for (var i = 1; i <= 3; i++) {
			var sourceDetails = getSettingsSource(i, mjd);
			dialHASets[2].add(sourceDetails[0]);
			if (storage_position.size() <= (i - 1)) {
				storage_position.add(sourceDetails[0]);
			}
			if ((sourceDetails[1] == true) || // Source changes position.
				(locationChanged == true) || // The location of the watch has changed.
				(storage_dialHASetsLow.size() <= (i - 1)) || // We haven't initialised.
				(distanceSources(storage_position[(i - 1)], // Source has different position.
								 sourceDetails[0]) > degreesToRadians(1.0d))
				) {
				// Calculate the new dial positions.
				dialHASets[0].add(haset_azel(sourceDetails[0][1], loc[0], sourceDetails[2]));
				dialHASets[1].add(haset_azel(sourceDetails[0][1], loc[0], sourceDetails[3]));
			} else {
				// We can just get the dial positions from storage.
				dialHASets[0].add(storage_dialHASetsLow[(i - 1)]);
				dialHASets[1].add(storage_dialHASetsMid[(i - 1)]);
			}
			
			// Add the dial positions to storage now.
			if (storage_dialHASetsLow.size() <= (i - 1)) {
				storage_dialHASetsLow.add(dialHASets[0]);
				storage_dialHASetsMid.add(dialHASets[1]);
			} else {
				storage_dialHASetsLow[(i - 1)] = dialHASets[0];
				storage_dialHASetsMid[(i - 1)] = dialHASets[1];
			}
			storage_position[(i - 1)] = sourceDetails[0];
		}
		return dialHASets;
	}
	
	// Calculate the distance between two source positions.
	function distanceSources(src1Pos, src2Pos) {
		var dist = Math.sqrt(Math.pow((src2Pos[0] - src1Pos[1]), 2) +
							 Math.pow((src2Pos[1] - src1Pos[1]), 2));
		// The distance is in radians.
		return dist;
	}
	
	// Get a source from the settings.
	static const SOURCE_TYPE_NAMED = 0;
	static const SOURCE_TYPE_RADEC = 1;
	static const SOURCE_NAMED_SUN = 0;
	function getSettingsSource(sourceNum, mjd) {
		if ((sourceNum < 1) || (sourceNum > 3)) {
			sourceNum = 1;
		}
		// Each setting is prefixed by this string.
		var srcPrefix = "Source" + sourceNum.format("%1d");
		// Get the elevation limits, which are independent of source type.
		var srcLowEl = Application.Properties.getValue(srcPrefix + "LowEl").toDouble();
		var srcMidEl = Application.Properties.getValue(srcPrefix + "MidEl").toDouble();
		
		// Do different things depending on the type of source the user has chosen.
		// But the return value is always an array:
		// [ [ ra (rad), dec (rad) ], changing (bool), lowEl (deg), midEl (deg) ]
		var srcType = Application.Properties.getValue(srcPrefix + "Type");
		if (srcType == SOURCE_TYPE_NAMED) {
			var srcName = Application.Properties.getValue(srcPrefix + "Name");
			if (srcName == SOURCE_NAMED_SUN) {
				return [ calculateSunPosition(mjd), true, srcLowEl, srcMidEl ];
			}
		} else if (srcType == SOURCE_TYPE_RADEC) {
			var srcRa = Application.Properties.getValue(srcPrefix + "Ra").toDouble();
			var srcDec = Application.Properties.getValue(srcPrefix + "Dec").toDouble();
			var srcPos = [ degreesToRadians(srcRa * 15.0d), degreesToRadians(srcDec) ];
			return [ srcPos, false, srcLowEl, srcMidEl ];
		}
		return [ [ 0.0d, 0.0d ], false, 0.0d, 12.0d ];
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
			// We have to draw non-illuminated sides too.
			dc.setColor(moonColour, Graphics.COLOR_TRANSPARENT);
			dc.fillCircle(middleX, middleY, innerRadius);
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
