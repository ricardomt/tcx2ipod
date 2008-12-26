require 'rexml/document'
require 'time'
require 'date'
include REXML

class MainController < ApplicationController

  # Garmin2iPod
  # Ricardo Matsushima Teixeira - ricardo@7runs.com
  #
  # Copyright (C) 2008 Ricardo Teixeira
  #
  #   This program is free software: you can redistribute it and/or modify
  #   it under the terms of the GNU General Public License as published by
  #   the Free Software Foundation, either version 3 of the License, or
  #   (at your option) any later version.
  #
  #   This program is distributed in the hope that it will be useful,
  #   but WITHOUT ANY WARRANTY; without even the implied warranty of
  #   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  #   GNU General Public License for more details.
  # 
  #   You should have received a copy of the GNU General Public License
  #   along with this program.  If not, see <http://www.gnu.org/licenses/>.
  #  
  #
  # This is a simple XML conversion application
  # to allow uploading of Garmin Forerunner data
  # to RunnerPlus.com
  #
  # Change History
  # --------------
  #
  # 2008-11-01 - Ruby File Created (RMT)
  # 2008-11-08 - Transplanted Ruby script into a Rails application (RMT)
  # 2008-12-01 - Included GPL text
  # 2008-12-01 - Adjusted stride length for stepcount
  # 2008-12-03 - Included handler for empty device name information on TCX (Ascent Export)
  # 2008-12-07 - Fixed issue #1 (Unknown device name) - for both "no device name" and "device name element empty" scenarios
  # 2008-12-07 - Fixed issues #2 (Timestamps discrepancies) and #3 (Weight conversion issue)
  # 2008-12-11 - Fixed issue #6 - GMT/UTC time offset error
  # 2008-12-26 - Fixed issue #7 - Miles versus Kilometers discrepancy on runSummary
  # 2008-12-26 - Fixed issue #5 - Playlist not visible in Runner+
  
  def upload
    uploaded_file = params[:TcxFile]
    data = uploaded_file.read if uploaded_file.respond_to? :read
    
    if request.post? and data 
      
      doc = Document.new(data)
      root = doc.root

      # Basic iPod data
      strRunSummaryVersion = "1"
      strRunSummaryWorkoutName = params[:TemplateName]
      strPlaylistName = params[:PlaylistName]
      # Included GMT offset - My Forerunner is set to record GMT hours
      # Looks like the Forerunner will always record UTC in the XML. Client must correct TZ offset
      strRunSummaryTime = root.elements["Activities/Activity/Id"].text
      timZuluTime = Time.parse(strRunSummaryTime)
      
      strTZOffset = params[:TimeZoneOffset]
      
      intOffset = case strTZOffset
        when "GMT-1200" : -43200
        when "GMT-1100" : -39600
        when "GMT-1000" : -36000
        when "GMT-0900" : -32400
        when "GMT-0800" : -28800
        when "GMT-0700" : -25200
        when "GMT-0600" : -21600
        when "GMT-0500" : -18000
        when "GMT-0400" : -14400
        when "GMT-0300" : -10800
        when "GMT-0200" : -7200
        when "GMT-0100" : -3600
        when "UTC/GMT"  : 0
        when "GMT+0100" : 3600
        when "GMT+0200" : 7200
        when "GMT+0300" : 10800
        when "GMT+0400" : 14400
        when "GMT+0500" : 18000
        when "GMT+0600" : 21600
        when "GMT+0700" : 25200
        when "GMT+0800" : 28800
        when "GMT+0900" : 32400
        when "GMT+1000" : 36000
        when "GMT+1100" : 39600
        when "GMT+1200" : 43200
      end
      
      # Offsets the starttime
      timAdjusted = timZuluTime + intOffset
      
      # and builds the final Time string
      if strTZOffset != "UTC/GMT" then
        strRunSummaryTime = timAdjusted.xmlschema.chop + strTZOffset[3..5] + ":00"
      else
        strRunSummaryTime = timAdjusted.xmlschema
      end

      # Takes Total Time in Seconds, Calories and TotalDistance from Garmin data
      numTotalTimeSeconds = 0.0
      numTotalCalories = 0
      numTotalDistance = 0.0
      arrUserClicksDuration = Array.new   # Creates Array object for userClicks snapshots (Duration) - Lap pushes on Garmin
      arrUserClicksDistance = Array.new   # Creates Array object for userClicks snapshots (Distance) - Lap pushes on Garmin

      # Iterates on Garmin Laps
      root.elements.each("//Lap") do |element|
        numTotalTimeSeconds = numTotalTimeSeconds + element.elements["TotalTimeSeconds"].text.to_f
        numTotalCalories = numTotalCalories + element.elements["Calories"].text.to_i
        numTotalDistance = numTotalDistance + element.elements["DistanceMeters"].text.to_f
        arrUserClicksDuration << (numTotalTimeSeconds * 1000).to_i   # stores in millisecond
        arrUserClicksDistance << numTotalDistance / 1000             # stores in km
      end
      puts "\n"

      # Stores the time in milliseconds for the iPod output
      numTotalTime_mSeconds = (numTotalTimeSeconds * 1000).to_i
      strRunSummaryDuration = numTotalTime_mSeconds.to_s
      puts "Total time: #{numTotalTime_mSeconds} ms"

      # Breaks down duration
      numDurationHours = (numTotalTimeSeconds / 3600).to_i
      numDurationMinutes = (numTotalTimeSeconds / 60).to_i - (numDurationHours * 60)
      numDurationSeconds = numTotalTimeSeconds.to_i - (numDurationHours * 3600) - (numDurationMinutes * 60)

      # Building strDurationString
      if numDurationHours != 0 then
        strDurationString = "%d:%02d:%02d" % [numDurationHours, numDurationMinutes, numDurationSeconds]
      else
        strDurationString = "%d:%02d" % [numDurationMinutes, numDurationSeconds]
      end

      # Building iPod entities
      strDistanceUnit = params[:DistanceUnit]
      numDivider = case strDistanceUnit
        when "km" : 1000
        when "mi" : 1609.344
      end 

      # Converts meter to either miles or kilometers
      numTotalDistanceUnits = numTotalDistance / numDivider

      # Formats output strings
      strDistance = "%.4f" % numTotalDistanceUnits
      strDistanceString = "%.2f #{strDistanceUnit}" % numTotalDistanceUnits

      # Calculates pace
      numAveragePaceTotalSeconds = (numTotalTimeSeconds / numTotalDistanceUnits).to_i
      numAveragePaceMinutes = (numAveragePaceTotalSeconds / 60).to_i
      numAveragePaceSeconds = (numAveragePaceTotalSeconds - (numAveragePaceMinutes * 60))
      strAveragePace = "%d:%02d min/%s" % [numAveragePaceMinutes, numAveragePaceSeconds, strDistanceUnit]

      # Debug output
      #puts "Duration: #{strDurationString}\n"
      #puts "Total Distance: #{strDistanceString}\n"
      #puts "Average Page: #{strAveragePace}\n"
      #puts "Total Calories: #{numTotalCalories}\n"

      # Dummy (maybe not-so-dummy) data for stepcounts
      numWalkBegin = 1
      numWalkEnd = 1 # I didn't walk, bro, I ran!
      numRunBegin = 1
      numRunEnd = (numTotalDistance / 1.5).to_i # Assuming a 1.5m stride (http://wiki.answers.com/Q/What_is_the_average_mans_running_stride_length)

      # Miscellaneous data - Some are dummy, some are real
      strTemplateID = params[:TemplateID]  # Put your template ID here
      strTemplateName = params[:TemplateName]   # I am always using basic for this script
      strEmpedID = params[:EmpedID]     # Put your EMPED ID here
      strWeightUnits = params[:WeightUnits] # Gets WeightUnits from the UI
      
      fltWeightAdjust = case strWeightUnits
        when "kg" : 1
        when "lb" : 0.45359237
      end
        
      strWeight = "%.1f" % (params[:Weight].to_f * fltWeightAdjust)  # Calculates weight in kg with 1 decimal place

      # Gets the device identifier
      if root.elements["Activities/Activity/Creator/Name"] != nil then
        if root.elements["Activities/Activity/Creator/Name"].text != nil then
          # Gets the Creator Name from the Garmin XML
          strDevice = root.elements["Activities/Activity/Creator/Name"].text + " - Converted by 7runs.com"
        else
          #  Device Name element is empty
          if params[:DeviceName] == "" or params[:DeviceName] == nil then
            strDevice = "Unknown Garmin Device - Converted by 7runs.com"
          else
            strDevice = params[:DeviceName] + " - Converted by 7runs.com"
          end
        end
      else
        # No Device Name element
        if params[:DeviceName] == "" or params[:DeviceName] == nil then
          strDevice = "Unknown Garmin Device - Converted by 7runs.com"
        else
          strDevice = params[:DeviceName] + " - Converted by 7runs.com"
        end
      end

      strCalibration = params[:Calibration]   # Calibration data from a valid iPod XML

      # Converts Trackpoint stream into Ruby Array
      arrTrackpointTime = Array.new         # Trackpoints Time array
      arrTrackpointDistance = Array.new     # Trackpoints Distance array
      arrExtendedData = Array.new           # Extended data Distance array - iPod
      arrKmSplitDuration = Array.new        # Snapshot array for kmSplit duration
      arrMileSplitDuration = Array.new      # Snapshot array for mileSplit duration
      arrKmSplitDistance = Array.new        # Snapshot array for kmSplit distance
      arrMileSplitDistance = Array.new      # Snapshot array for mileSplit distance

      # First datapoint on Extended Data for iPod shall be 0.0
      arrExtendedData << 0.0
      timPointTimePrevious = Time.parse(strRunSummaryTime)
      numPointDistancePrevious = 0.0
      numKmSplitDistancePrevious = 0.0
      numMileSplitDistancePrevious = 0.0

      # Populates the arrays
        root.elements.each("//Trackpoint") do |element|
          if ((element.elements["Time"] != nil) and (element.elements["DistanceMeters"] != nil)) then

            # Extracting data from XML elements
            strPointTime = element.elements["Time"].text
            strPointDistance = element.elements["DistanceMeters"].text

            # Type casting for time and distance values of the current trackpoint
            timPointTimeCurrent = Time.parse(strPointTime)
            numPointDistanceCurrent = strPointDistance.to_f

            # Looks for time interval equal or greater than 10s between last recorded ExtendedData point and current trackpoint
            numIntervalTime = timPointTimeCurrent - timPointTimePrevious
            if numIntervalTime >= 10 then
              # Interpolates to a 10 sec sample
              numIntervalDistance = numPointDistanceCurrent - numPointDistancePrevious
              numDistanceSoFar10s = numPointDistancePrevious + ((numIntervalDistance / numIntervalTime) * 10)

              arrExtendedData << (numDistanceSoFar10s / 1000)    # Garmin records meters, iPod records kms
              # Sets Previous to Current trackpoint for next iteration
              numPointDistancePrevious = numDistanceSoFar10s
              timPointTimePrevious = timPointTimePrevious + 10
            end

            # Looks for kmSplit and mileSplit features - Doesn't interpolate, just catches the closest larger duration
            numKmSplitDistance = numPointDistanceCurrent - numKmSplitDistancePrevious
            numMileSplitDistance = numPointDistanceCurrent- numMileSplitDistancePrevious
            # Catches km splits
            if numKmSplitDistance >= 1000 then
              arrKmSplitDuration << ((timPointTimeCurrent - Time.parse(strRunSummaryTime)) * 1000).to_i
              arrKmSplitDistance << (numPointDistanceCurrent / 1000)
              numKmSplitDistancePrevious = numKmSplitDistancePrevious + 1000
            end
            # Catches mile splits
            if numMileSplitDistance >= 1609.344 then
              arrMileSplitDuration << ((timPointTimeCurrent - Time.parse(strRunSummaryTime)) * 1000).to_i
              arrMileSplitDistance << (numPointDistanceCurrent / 1000) # even for mile splits, stores km
              numMileSplitDistancePrevious = numPointDistanceCurrent
            end

            # There is no need to populate the following arrays. This was used during development only.
            # arrTrackpointTime << strPointTime
            # arrTrackpointDistance << strPointDistance.to_f

          end
        end
      #end

      # Debug outputs
      #puts "#{arrTrackpointTime.size} Garmin Trackpoints for time"
      #puts "#{arrTrackpointDistance.size} Garmin Trackpoints for distance"
      #puts "#{arrExtendedData.size} iPod ExtendedData points for distance"
      #puts "#{arrUserClicksDistance.size} iPod UserClick points for distance"
      #puts "#{arrUserClicksDuration.size} iPod UserClick points for duration"
      #puts "#{arrKmSplitDistance.size} iPod km Split points for distance"
      #puts "#{arrKmSplitDuration.size} iPod km Split points for duration"
      #puts "#{arrMileSplitDistance.size} iPod mile Split points for distance"
      #puts "#{arrMileSplitDuration.size} iPod mile Split points for duration"

      # --------------------------------------------------------
      # From this point and on, we will be creating the iPod XML
      # --------------------------------------------------------

      # Version info
      output = Document.new('<?xml version="1.0" encoding="UTF-8"?>')

      # Headers
      output.add_element("sportsData")
      output.root.add_element("vers")
      output.root.elements["vers"].text = strRunSummaryVersion

      # runSummary
      output.root.add_element("runSummary")
      eleRunSummary = output.root.elements["runSummary"]
      eleRunSummary.add_element("workoutName")
      eleRunSummary.elements["workoutName"].text = strRunSummaryWorkoutName
      eleRunSummary.add_element("time")
      eleRunSummary.elements["time"].text = strRunSummaryTime
      eleRunSummary.add_element("duration")
      eleRunSummary.elements["duration"].text = strRunSummaryDuration
      eleRunSummary.add_element("durationString")
      eleRunSummary.elements["durationString"].text = strDurationString
      eleRunSummary.add_element("distance", { "unit" => "km" })                         # Distance VALUES on runSummary is always in km
      eleRunSummary.elements["distance"].text = "%.04f" % (numTotalDistance / 1000)      # Value in km (strings are in mi or km)
      eleRunSummary.add_element("distanceString")
      eleRunSummary.elements["distanceString"].text = strDistanceString
      eleRunSummary.add_element("pace")
      eleRunSummary.elements["pace"].text = strAveragePace
      eleRunSummary.add_element("calories")
      eleRunSummary.elements["calories"].text = numTotalCalories.to_s
      eleRunSummary.add_element("battery")
      eleRunSummary.add_element("playlistList")
      eleRunSummary.elements["playlistList"].add_element("playlist")
      eleRunSummary.elements["playlistList"].elements["playlist"].add_element("playlistName")
      eleRunSummary.elements["playlistList"].elements["playlist"].elements["playlistName"].text = CData.new(strPlaylistName)
      eleRunSummary.add_element("stepCounts")
      eleStepCounts = eleRunSummary.elements["stepCounts"]
      eleStepCounts.add_element("walkBegin")
      eleStepCounts.add_element("walkEnd")
      eleStepCounts.add_element("runBegin")
      eleStepCounts.add_element("runEnd")
      eleStepCounts.elements["walkBegin"].text = numWalkBegin.to_s
      eleStepCounts.elements["walkEnd"].text = numWalkEnd.to_s
      eleStepCounts.elements["runBegin"].text = numRunBegin.to_s
      eleStepCounts.elements["runEnd"].text = numRunEnd.to_s

      # Miscellaneous data - Template info
      output.root.add_element("template")
      eleTemplate = output.root.elements["template"]
      eleTemplate.add_element("templateID")
      eleTemplate.add_element("templateName")
      eleTemplate.elements["templateID"].text = strTemplateID
      eleTemplate.elements["templateName"].text = strTemplateName

      # Goal
      output.root.add_element("goal")
      output.root.elements["goal"].add_attribute("type", "")
      output.root.elements["goal"].add_attribute("value", "")
      output.root.elements["goal"].add_attribute("unit", "")

      # Userinfo
      output.root.add_element("userInfo")
      output.root.elements["userInfo"].add_element("empedID")
      output.root.elements["userInfo"].elements["empedID"].text = strEmpedID
      output.root.elements["userInfo"].add_element("weight")
      output.root.elements["userInfo"].elements["weight"].text = strWeight
      output.root.elements["userInfo"].add_element("device")
      output.root.elements["userInfo"].elements["device"].text = strDevice
      output.root.elements["userInfo"].add_element("calibration")
      output.root.elements["userInfo"].elements["calibration"].text = strCalibration

      # StartTime
      output.root.add_element("startTime")
      output.root.elements["startTime"]

      # Snapshots 1 - UserClicks
      output.root.add_element("snapShotList", { "snapShotType" => "userClick" })
      eleSnapshot = output.root.elements["snapShotList[1]"]
      arrUserClicksDuration.each_index do |index|
        eleSnapshot.add_element("snapShot", { "event" => "onDemandVP" })
        eleSnapshot.elements["snapShot[#{index + 1}]"].add_element("duration")
        eleSnapshot.elements["snapShot[#{index + 1}]"].add_element("distance")
        eleSnapshot.elements["snapShot[#{index + 1}]"].elements["duration"].text = arrUserClicksDuration[index]
        eleSnapshot.elements["snapShot[#{index + 1}]"].elements["distance"].text = "%.4f" % arrUserClicksDistance[index]
      end

      # Snapshots 2 - km Splits
      output.root.add_element("snapShotList", { "snapShotType" => "kmSplit" })
      eleSnapshot = output.root.elements["snapShotList[2]"]
      arrKmSplitDuration.each_index do |index|
        eleSnapshot.add_element("snapShot")
        eleSnapshot.elements["snapShot[#{index + 1}]"].add_element("duration")
        eleSnapshot.elements["snapShot[#{index + 1}]"].add_element("distance")
        eleSnapshot.elements["snapShot[#{index + 1}]"].elements["duration"].text = arrKmSplitDuration[index]
        eleSnapshot.elements["snapShot[#{index + 1}]"].elements["distance"].text = "%.4f" % arrKmSplitDistance[index]
      end

      # Snapshots 3 - mile Splits
      output.root.add_element("snapShotList", { "snapShotType" => "mileSplit" })
      eleSnapshot = output.root.elements["snapShotList[3]"]
      arrMileSplitDuration.each_index do |index|
        eleSnapshot.add_element("snapShot")
        eleSnapshot.elements["snapShot[#{index + 1}]"].add_element("duration")
        eleSnapshot.elements["snapShot[#{index + 1}]"].add_element("distance")
        eleSnapshot.elements["snapShot[#{index + 1}]"].elements["duration"].text = arrMileSplitDuration[index]
        eleSnapshot.elements["snapShot[#{index + 1}]"].elements["distance"].text = "%.4f" % arrMileSplitDistance[index]
      end

      # At last, the extendedData Stream
      strExtendedDataFinal = ""
      output.root.add_element("extendedDataList")
      eleExtendedData = output.root.elements["extendedDataList"]
      eleExtendedData.add_element("extendedData")
      eleExtendedData.elements["extendedData"].add_attribute("dataType", "distance")
      eleExtendedData.elements["extendedData"].add_attribute("intervalType", "time")
      eleExtendedData.elements["extendedData"].add_attribute("intervalUnit", "s")
      eleExtendedData.elements["extendedData"].add_attribute("intervalValue", "10")

      arrExtendedData.each_index do |index|
        if index == 0 then
          strExtendedDataFinal = arrExtendedData[index].to_s
        else
          strExtendedDataFinal = "#{strExtendedDataFinal}, %.4f" % arrExtendedData[index]
        end
      end

      eleExtendedData.elements["extendedData"].text = strExtendedDataFinal

      timFile = Time.parse(strRunSummaryTime)
      strFileName = "#{timFile.year}-%02d-%02d %02d;%02d;%02d.xml" % [timFile.month, timFile.day, timFile.hour, 
timFile.min, timFile.sec] 

      # Hijacks the output, bypassing the output view - Sends the XML back to the client
      # send_data(output, :type => "application/octet-stream", :filename => strFileName ) 

      response.body = output.to_s
      response.content_type = "text/xml"
      filename = strFileName
      response.headers['Content-disposition'] = "Attachment; filename=\"#{filename}\""
      render :text => output.to_s

      #outputFile = File.new(strFileName, "w+")
      #outputFile << output

      #puts "Output file generated: #{strFileName}"

    else 
      redirect_to :action => 'index' 
    end
  end  
end
