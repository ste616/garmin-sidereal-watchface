using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;
using Toybox.Application;
using Toybox.Time.Gregorian;
using Toybox.Time;

class GarminSiderealWatchfaceView extends WatchUi.WatchFace {

	// Some parameters to control how the watch face looks.
    static const HOUR_TICK_LENGTH = 10;
	var ZERO_RADIANS;
	var middleX;
	var middleY;
	var thirdX;
	var thirdY;
	var quarterX;
	var quarterY;
	var arcRadius;
	var sunRadius;
	var SIDEREAL_HAND_LENGTH;

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
		sunRadius = deviceSettings.screenHeight / 2.0;

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

    // Update the view
    function onUpdate(dc) {
    	// Get the current time, both local and UTC.
        var utcTime = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        var clockTime = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    
    	// Calculate the MJD.
        var mjd = utcToMjd(utcTime);

		// Work out where we should calculate the LST for.
    	var loc = earthLocation("atca");
        
        // Calculate the sidereal time.
        var lst = mjdToLst(mjd, (loc[1].toDouble() / 360.0d), 0.0d);

        // Format the time into a string.
        var timeStringLocal = formatTime(clockTime);
        var timeStringUTC = formatTime(utcTime);
        var dateStringLocal = formatDate(clockTime);
        var doyString = formatDOY();
        var mjdString = formatMJD();

        // Update the view.
		dc.setColor( Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK );
		dc.clear();

		// Draw the 24 hours of the sidereal clock dial.
		drawSiderealDial(dc);

		// Draw the text stuff.
		drawFaceText(dc, timeStringLocal, timeStringUTC, dateStringLocal, doyString, mjdString);
		
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

	// Given any number, put it between 0 and 1.
	function turnFraction(f) {
		if (f > 1.0d) {
			f -= f.toNumber().toDouble();
		}
		while (f < 0.0d) {
			f += 1.0d;
		}
		return (f);
	}

	// Calculate the sidereal time at Greenwich, given an MJD.
	function gst(mjd, dUT1) {
		if ((dUT1 > 0.5d) || (dUT1 < -0.5d)) {
			System.println("dUT1 is out of range at " + dUT1.format("%.4f"));
			return 0.0d;
		}
		var JULIAN_DAY_J2000 = 2451545.0d;
		var JULIAN_DAYS_IN_CENTURY = 36525.0d;
		var SOLAR_TO_SIDEREAL = 1.002737909350795d;
		
		var a = 101.0d + 24110.54581d / 86400.0d;
		var b = 8640184.812866d / 86400.0d;
		var e = 0.093104d / 86400.0d;
		var d = 0.0000062d / 86400.0d;
		var tu = (mjd.toNumber().toDouble() - (JULIAN_DAY_J2000 - 2400000.5d)) / JULIAN_DAYS_IN_CENTURY;
		var sidtim = turnFraction(a + tu * (b + tu * (e - tu * d)));
		var gmst = turnFraction(sidtim + (mjd - mjd.toNumber().toDouble() + dUT1 / 86400.0d) * SOLAR_TO_SIDEREAL);
		
		return gmst;
	}

	// Calculate the sidereal time at some longitude on the Earth.
	function mjdToLst(mjd, longitude, dUT1) {
		var lst = turnFraction(gst(mjd, dUT1) + longitude);
		
		return lst;
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
		var points = calcLineFromCircleEdge(arcRadius, 2.0 * HOUR_TICK_LENGTH, ZERO_RADIANS);
		dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
		dc.setPenWidth(7);
		dc.drawLine(points[0], points[1], points[2], points[3]);
		dc.setPenWidth(5);
		for (var i = 1; i < 24; i++) {
			var dayFrac = i.toDouble() / 24.0d;
			var radian = ZERO_RADIANS + dayFrac * Math.PI * 2.0d;
			points = calcLineFromCircleEdge(arcRadius - 1.1 * HOUR_TICK_LENGTH, HOUR_TICK_LENGTH / 4.0, radian);
			dc.drawLine(points[0], points[1], points[2], points[3]);
		}
		dc.setPenWidth(1);

	}

	// Draw all the text elements on the face.
	function drawFaceText(dc, localTimeString, utcTimeString, dateString, doyString, mjdString) {
		// The colour of the local time.
		var localColour = Graphics.COLOR_YELLOW;
		// Draw the local text string.		
		var localText = new WatchUi.Text({
			:text=>localTimeString, :color=>localColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>thirdX, :locY=>thirdY });
		localText.draw(dc);
		// Make the "LOC" label.
		var localLabel = new WatchUi.Text({
			:text=>"LOC", :color=>localColour,
			:justification=>Graphics.TEXT_JUSTIFY_RIGHT,
			:font=>Graphics.FONT_XTINY, :locX=>(thirdX + (localText.width / 2)),
			:locY=>(thirdY - localText.height) });
		localLabel.draw(dc);
		
		// The colour of the UTC time.
		var utcColour = Graphics.COLOR_GREEN;
		// Draw the UTC text string.
		var utcText = new WatchUi.Text({
			:text=>utcTimeString, :color=>utcColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>(2 * thirdX), :locY=>thirdY });
		utcText.draw(dc);
		// Make the "UTC" label.
		var utcLabel = new WatchUi.Text({
			:text=>"UTC", :color=>utcColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_XTINY, :locX=>((2 * thirdX) - (utcText.width / 2)),
			:locY=>(thirdY - utcText.height) });
		utcLabel.draw(dc);
		
		// Draw the local date.
		var dateText = new WatchUi.Text({
			:text=>dateString, :color=>localColour,
			:justification=>Graphics.TEXT_JUSTIFY_CENTER,
			:font=>Graphics.FONT_SMALL, :locX=>middleX,
			:locY=>(thirdX + localText.height) });
		dateText.draw(dc);
		
		// Draw the DOY.
		var doyLineY = thirdX + localText.height + (0.9 * dateText.height);
		var doyText = new WatchUi.Text({
			:text=>doyString, :color=>localColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>(thirdX - (localText.width / 2.0)),
			:locY=>doyLineY });
		doyText.draw(dc);
		// And the label.
		var doyLabel = new WatchUi.Text({
			:text=>"D", :color=>localColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_SYSTEM_XTINY, :locX=>(doyText.locX + (0.9 * doyText.width)),
			:locY=>(doyLineY - (0.23 * doyText.height)) });
		doyLabel.draw(dc); 
		
		// Draw the MJD.
		var mjdText = new WatchUi.Text({
			:text=>mjdString, :color=>utcColour,
			:justification=>Graphics.TEXT_JUSTIFY_LEFT,
			:font=>Graphics.FONT_NUMBER_MILD, :locX=>middleX,
			:locY=>doyLineY });
		mjdText.draw(dc);
		var mjdLabel = new WatchUi.Text({
			:text=>"J ", :color=>utcColour,
			:justification=>Graphics.TEXT_JUSTIFY_RIGHT,
			:font=>Graphics.FONT_SYSTEM_XTINY, :locX=>mjdText.locX,
			:locY=>(doyLineY + (0.2 * doyText.height)) });
		mjdLabel.draw(dc);
	}

}
