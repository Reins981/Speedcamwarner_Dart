# -*-coding:utf8;-*-
# qpy:2
# ts=4:sw=4:expandtab
'''
Created on 01.07.2014

@author: rkoraschnigg
'''
import json
import os
import platform

from Logger import Logger
from ThreadBase import StoppableThread
from kivy.core.audio import SoundLoader
from kivy.clock import Clock
from functools import partial
from dialogflow_client import DialogflowClient
from ServiceAccount import SERVICE_ACCOUNT, load_service_account
from google.cloud import texttospeech
from jnius import autoclass
import pyttsx3

BASE_PATH = os.path.join(os.path.abspath(os.path.dirname(__file__)), "sounds")


class VoicePromptThread(StoppableThread, Logger):
    def __init__(self, main_app,
                 resume, cv_voice, voice_prompt_queue, calculator, cond, log_viewer):
        StoppableThread.__init__(self)
        Logger.__init__(self, self.__class__.__name__, log_viewer)
        self.main_app = main_app
        self.resume = resume
        self.cv_voice = cv_voice
        self.voice_prompt_queue = voice_prompt_queue
        self.calculator = calculator
        self.cond = cond
        # thread lock
        self._lock = False

        json_data = load_service_account()
        project_id = json_data["project_id"]
        self.dialogflow_client = DialogflowClient(project_id=project_id)

        self.set_configs()

    def set_configs(self):
        # Set configurations for the voice prompt thread
        self.ai_voice_prompts = True

    def run(self):
        while not self.cond.terminate:
            if self.main_app.run_in_back_ground:
                self.main_app.main_event.wait()
            if not self.resume.isResumed():
                self.voice_prompt_queue.clear_gpssignalqueue(self.cv_voice)
                self.voice_prompt_queue.clear_maxspeedexceededqueue(self.cv_voice)
                self.voice_prompt_queue.clear_onlinequeue(self.cv_voice)
                self.voice_prompt_queue.clear_arqueue(self.cv_voice)
            else:
                self.process()

        self.voice_prompt_queue.clear_gpssignalqueue(self.cv_voice)
        self.voice_prompt_queue.clear_maxspeedexceededqueue(self.cv_voice)
        self.voice_prompt_queue.clear_onlinequeue(self.cv_voice)
        self.print_log_line(f"{self.__class__.__name__} terminating")
        self.stop()

    def play_sound(self, *args):
        sound = args[0]
        self.print_log_line(f" Trigger sound {sound}")
        s = SoundLoader.load(sound)
        s.buffer = 16384
        if s:
            s.play()
            Clock.schedule_once(lambda dt: self.on_sound_playback_finished(s), s.length)
        else:
            self._lock = False

    def on_sound_playback_finished(self, sound):
        self.print_log_line('Playback finished')
        sound.stop()
        sound.unload()
        self._lock = False

    def synthesize_speech(self, text, output_path):
        client = texttospeech.TextToSpeechClient()

        input_text = texttospeech.SynthesisInput(text=text)

        voice = texttospeech.VoiceSelectionParams(
            language_code="en-US",
            ssml_gender=texttospeech.SsmlVoiceGender.NEUTRAL
        )

        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.LINEAR16  # = .wav PCM format
        )

        response = client.synthesize_speech(
            input=input_text, voice=voice, audio_config=audio_config
        )

        with open(output_path, "wb") as out:
            out.write(response.audio_content)

    @staticmethod
    def speak_android(text):
        PythonActivity = autoclass('org.kivy.android.PythonActivity')
        TextToSpeech = autoclass('android.speech.tts.TextToSpeech')
        Locale = autoclass('java.util.Locale')

        tts = TextToSpeech(PythonActivity.mActivity, None)
        tts.setLanguage(Locale.US)
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, None, None)

    @staticmethod
    def speak_desktop(text):
        engine = pyttsx3.init()
        rate = engine.getProperty('rate')
        engine.setProperty('rate', int(rate * 0.80))  # Reduce speed by 15%
        engine.say(text)
        engine.runAndWait()

    def process(self):
        voice_entry = self.voice_prompt_queue.consume_items(self.cv_voice)
        self.cv_voice.release()

        while self._lock:
            pass

        if self.ai_voice_prompts:
            # Use Dialogflow to generate a response
            response = self.dialogflow_client.detect_intent(text=voice_entry)
            self.print_log_line(f"Dialogflow response: {response}")

            # Convert Dialogflow response text to speech
            sound = os.path.join(BASE_PATH, 'response.wav')
            if platform == "android":
                self._lock = True
                # self.synthesize_speech(response, sound)
                VoicePromptThread.speak_android(response)
                self._lock = False
            else:
                self._lock = True
                VoicePromptThread.speak_desktop(response)
                # self.synthesize_speech(response, sound)
                self._lock = False
            # if os.path.exists(sound) and os.path.getsize(sound) > 0:
            # self._lock = True
            # self.play_sound(sound)
        else:
            sound = None
            if voice_entry == "EXIT_APPLICATION":
                sound = os.path.join(BASE_PATH, 'app_exit.wav')
            elif voice_entry == "ADDED_POLICE":
                sound = os.path.join(BASE_PATH, 'police_added.wav')
            elif voice_entry == "ADDING_POLICE_FAILED":
                sound = os.path.join(BASE_PATH, 'police_failed.wav')
            elif voice_entry == "STOP_APPLICATION":
                sound = os.path.join(BASE_PATH, 'app_stopped.wav')
            elif voice_entry == "OSM_DATA_ERROR":
                # sound = os.path.join(BASE_PATH, 'data_error.wav')
                sound = None
            elif voice_entry == "INTERNET_CONN_FAILED":
                sound = os.path.join(BASE_PATH, 'inet_failed.wav')
            elif voice_entry == "HAZARD":
                sound = os.path.join(BASE_PATH, 'hazard.wav')
                # hazard warning on the road
            elif voice_entry == "EMPTY_DATASET_FROM_SERVER":
                # sound = os.path.join(BASE_PATH, 'empty_data.wav')
                sound = None
            elif voice_entry == "LOW_DOWNLOAD_DATA_RATE":
                sound = os.path.join(BASE_PATH, 'low_download_rate.wav')
            elif voice_entry == "GPS_OFF":
                sound = os.path.join(BASE_PATH, 'gps_off.wav')
            elif voice_entry == "GPS_LOW":
                sound = os.path.join(BASE_PATH, 'gps_weak.wav')
            elif voice_entry == "GPS_ON":
                sound = os.path.join(BASE_PATH, 'gps_established.wav')
            elif voice_entry == "SPEEDCAM_BACKUP":
                sound = os.path.join(BASE_PATH, 'camera_backup.wav')
            elif voice_entry == "SPEEDCAM_REINSERT":
                sound = os.path.join(BASE_PATH, 'speed_cam_reinserted.wav')
            elif voice_entry == "FIX_100":
                sound = os.path.join(BASE_PATH, 'fix_100.wav')
            elif voice_entry == "TRAFFIC_100":
                sound = os.path.join(BASE_PATH, 'traffic_100.wav')
            elif voice_entry == "MOBILE_100":
                sound = os.path.join(BASE_PATH, 'mobile_100.wav')
            elif voice_entry == "DISTANCE_100":
                sound = os.path.join(BASE_PATH, 'distance_100.wav')
            elif voice_entry == "FIX_300":
                sound = os.path.join(BASE_PATH, 'fix_300.wav')
            elif voice_entry == "TRAFFIC_300":
                sound = os.path.join(BASE_PATH, 'traffic_300.wav')
            elif voice_entry == "MOBILE_300":
                sound = os.path.join(BASE_PATH, 'mobile_300.wav')
            elif voice_entry == "DISTANCE_300":
                sound = os.path.join(BASE_PATH, 'distance_300.wav')
            elif voice_entry == "FIX_500":
                sound = os.path.join(BASE_PATH, 'fix_500.wav')
            elif voice_entry == "TRAFFIC_500":
                sound = os.path.join(BASE_PATH, 'traffic_500.wav')
            elif voice_entry == "MOBILE_500":
                sound = os.path.join(BASE_PATH, 'mobile_500.wav')
            elif voice_entry == "DISTANCE_500":
                sound = os.path.join(BASE_PATH, 'distance_500.wav')
            elif voice_entry == "FIX_1000":
                sound = os.path.join(BASE_PATH, 'fix_1000.wav')
            elif voice_entry == "TRAFFIC_1000":
                sound = os.path.join(BASE_PATH, 'traffic_1000.wav')
            elif voice_entry == "MOBILE_1000":
                sound = os.path.join(BASE_PATH, 'mobile_1000.wav')
            elif voice_entry == "DISTANCE_1000":
                sound = os.path.join(BASE_PATH, 'distance_1000.wav')
            elif voice_entry == "FIX_NOW":
                sound = os.path.join(BASE_PATH, 'fix_now.wav')
            elif voice_entry == "TRAFFIC_NOW":
                sound = os.path.join(BASE_PATH, 'traffic_now.wav')
            elif voice_entry == "MOBILE_NOW":
                sound = os.path.join(BASE_PATH, 'mobile_now.wav')
            elif voice_entry == "DISTANCE_NOW":
                sound = os.path.join(BASE_PATH, 'distance_now.wav')
            elif voice_entry == "CAMERA_AHEAD":
                sound = os.path.join(BASE_PATH, 'camera_ahead.wav')
            elif voice_entry == "WATER":
                sound = os.path.join(BASE_PATH, 'water.wav')
            elif voice_entry == "ACCESS_CONTROL":
                sound = os.path.join(BASE_PATH, 'access_control.wav')
            elif voice_entry == "POI_SUCCESS":
                sound = os.path.join(BASE_PATH, 'poi_success.wav')
            elif voice_entry == "POI_FAILED":
                sound = os.path.join(BASE_PATH, 'poi_failed.wav')
            elif voice_entry == "NO_ROUTE":
                sound = os.path.join(BASE_PATH, 'no_route.wav')
            elif voice_entry == "ROUTE_STOPPED":
                sound = os.path.join(BASE_PATH, 'route_stopped.wav')
            elif voice_entry == "POI_REACHED":
                sound = os.path.join(BASE_PATH, 'poi_reached.wav')
            elif voice_entry == "ANGLE_MISMATCH":
                sound = os.path.join(BASE_PATH, 'angle_mismatch.wav')
            elif voice_entry == "AR_HUMAN":
                sound = os.path.join(BASE_PATH, 'human.wav')
            else:
                pass

            if sound is not None:
                self._lock = True
                Clock.schedule_once(partial(self.play_sound, sound), 1)
