import os.path
from ThreadBase import StoppableThread
from geopy.geocoders import Nominatim
from Logger import Logger
from functools import partial
from kivy_garden.mapview import MapMarker, MapLayer
from kivy.graphics import Color, Line
from kivy.clock import Clock
from kivy.graphics.context_instructions import Translate, Scale
from kivy.metrics import dp
from MapUtils import *
from socket import gaierror
from urllib3.exceptions import NewConnectionError
URL = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'assets', 'leaf.html')
CAR_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'car1.png')
FIX_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'fixcamera_map.png')
TRAFFIC_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'trafficlightcamera_map.jpg')
MOBILE_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'mobilecamera_map.jpg')
DISTANCE_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'distancecamera_map.jpg')
HOSPITAL_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'hospital.jpg')
GAS_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'fuel.jpg')
UNDEFINED_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'undefined.jpg')
CONSTRUCTION_ICON = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'constructions.jpg')
CONSTRUCTION_MARKER = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'construction_marker.png')
POI_MARKER = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'images', 'poi_marker.png')
class LineMapLayer(MapLayer):
    colors = [Color(0, 0.4, 0.3, 1), Color(0, 0.5, 0.5, 1), Color(0, 1, 1, 1), Color(0, 1, 0.1, 1), Color(1, 0.2, 0.7, 1), Color(1, 1, 0.5, 1), Color(0, 0.1, 0.1, 1), Color(1, 0, 0, 1), Color(0, 1, 0, 1)]
    def __init__(self, *args, **kwargs):
        self.coordinates = args[0]
        self.color_index = args[1]
        self.mapview = args[2]
        self.layers = args[3]
        self.zoom = 0
        super().__init__(**kwargs)
    def reposition(self):
        if self.zoom != self.mapview.zoom:
            if len(self.layers) > 0:
                self.draw_lines()
    def draw_lines(self, *args, **kwargs):
        first = self.mapview.get_window_xy_from(self.coordinates[0], self.coordinates[3], self.mapview.zoom)
        second = self.mapview.get_window_xy_from(self.coordinates[2], self.coordinates[3], self.mapview.zoom)
        third = self.mapview.get_window_xy_from(self.coordinates[2], self.coordinates[1], self.mapview.zoom)
        fourth = self.mapview.get_window_xy_from(self.coordinates[0], self.coordinates[1], self.mapview.zoom)
        fifth = self.mapview.get_window_xy_from(self.coordinates[0], self.coordinates[3], self.mapview.zoom)
        scatter = self.mapview._scatter
        x, y, s = (scatter.x, scatter.y, scatter.scale)
        point_list = [first[0], first[1], second[0], second[1], third[0], third[1], fourth[0], fourth[1], fifth[0], fifth[1]]
        with self.canvas:
            self.canvas.clear()
            Scale(1 / s, 1 / s, 1)
            Translate(-x, -y)
            if self.color_index == 0:
                Color(0, 0, 1, 1)
            elif self.color_index == 1:
                Color(1, 1, 0, 1)
            elif self.color_index == 2:
                Color(1, 0, 0, 1)
            elif self.color_index == 3:
                Color(0, 1, 0, 1)
            elif self.color_index == 4:
                Color(1, 0, 1, 1)
            else:
                Color(0, 1, 1, 1)
            Line(points=point_list, width=4, joint='bevel')
class OSMThread(StoppableThread, Logger):
    pois_drawn = False
    route_calc = True
    POIS = []
    trigger = 'DRAW_POIS'
    def __init__(self, main_app, resume, osm_wrapper, calculator_thread, cv_map, cv_poi, map_queue, poi_queue, gps_producer, voice_consumer, cond, log_viewer):
        StoppableThread.__init__(self)
        Logger.__init__(self, self.__class__.__name__, log_viewer)
        self.main_app = main_app
        self.resume = resume
        self.osm_wrapper = osm_wrapper
        self.calculator_thread = calculator_thread
        self.osm_wrapper.set_calculator_thread(self.calculator_thread)
        self.cv_map = cv_map
        self.cv_poi = cv_poi
        self.map_queue = map_queue
        self.poi_queue = poi_queue
        self.cond = cond
        self.voice_consumer = voice_consumer
        self.gps_thread = gps_producer
        self.startup = True
        self.last_route = None
    def run(self):
        while not self.cond.terminate:
            if self.main_app.run_in_back_ground:
                self.main_app.main_event.wait()
            if not self.resume.isResumed():
                self.map_queue.clear_map_update(self.cv_map)
                self.poi_queue.clear(self.cv_poi)
            else:
                self.process()
        self.print_log_line(f'{self.__class__.__name__} terminating')
        self.stop()
    def process(self):
        item = self.map_queue.consume(self.cv_map)
        self.cv_map.release()
        pois = self.poi_queue.consume(self.cv_poi)
        self.cv_poi.release()
        while self.voice_consumer._lock:
            pass
        if isinstance(pois, list):
            OSMThread.trigger = 'DRAW_POIS'
            OSMThread.POIS = pois
            if len(OSMThread.POIS) > 0:
                OSMThread.pois_drawn = False
            try:
                self.osm_wrapper.draw_map(geo_rectangle_available=self.calculator_thread.get_osm_data_state())
            except (gaierror, NewConnectionError) as error:
                self.print_log_line(error, log_level='ERROR')
        elif isinstance(pois, tuple):
            OSMThread.trigger = 'CALCULATE_ROUTE_TO_NEAREST_POI'
            if pois is not None:
                self.last_route = pois
        if item == 'EXIT':
            return
        elif item == 'UPDATE':
            try:
                self.osm_wrapper.draw_map(geo_rectangle_available=self.calculator_thread.get_osm_data_state())
            except (gaierror, NewConnectionError) as error:
                self.print_log_line(error, log_level='ERROR')
class Maps(Logger):
    TRIGGER_RECT_DRAW = False
    TRIGGER_RECT_DRAW_EXTRAPOLATED = False
    def __init__(self, map_layout, cv_map_osm, cv_map_construction, cv_map_cloud, cv_map_db, map_queue, log_viewer):
        Logger.__init__(self, self.__class__.__name__, log_viewer)
        self.map_layout = map_layout
        self.cv_map_osm = cv_map_osm
        self.cv_map_construction = cv_map_construction
        self.cv_map_cloud = cv_map_cloud
        self.cv_map_db = cv_map_db
        self.map_queue = map_queue
        self.markers = []
        self.markers_cams = []
        self.markers_pois = []
        self.markers_construction_areas = []
        self.line_layers = []
        self.geoBounds = []
        self.geoBounds_extrapolated = []
        self.extrapolated = False
        self.first_start = True
        self.centerLat = None
        self.centerLng = None
        self.heading = None
        self.bearing = None
        self.accuracy = None
        self.calculator = None
        self.href_osm = '"http://openstreetmap.org"'
        self.href_lic = '"http://creativecommons.org/licenses/by-sa/2.0/"'
        self.href_mapbox = '"http://mapbox.com"'
        self.geoBoundsExtrapolated = []
        self.most_propable_heading_extrapolated = []
        self.colors = ['#ff7800', '#1100ff', '#00ff11', '#9100ff', '#eeff00', '#00eeff', '#ff00ee', '#584dff', '#4d9bff']
        self.app = Nominatim(user_agent='ReverseGeocoder')
        self.set_configs()
    def set_calculator_thread(self, calculator):
        self.calculator = calculator
    def set_configs(self):
        self.draw_rects = True
    def get_address_by_location(self, latitude, longitude, language='en'):
        coordinates = f'{latitude}, {longitude}'
        try:
            return self.app.reverse(coordinates, language=language).raw
        except:
            return ''
    def reset_geo_bounds_extrapolated(self, *args, **kwargs):
        del self.geoBoundsExtrapolated[:]
        for l in self.line_layers:
            self.map_layout.map_view.remove_layer(l)
        self.line_layers.clear()
    def reset_geo_bounds(self, *args, **kwargs):
        del self.geoBounds[:]
        for l in self.line_layers:
            self.map_layout.map_view.remove_layer(l)
        self.line_layers.clear()
    def osm_update_center(self, lat, lng):
        self.centerLat = lat
        self.centerLng = lng
    def setExtrapolation(self, extrapolated):
        self.extrapolated = extrapolated
    def osm_update_heading(self, heading):
        self.heading = heading
    def osm_update_bearing(self, bearing):
        self.bearing = bearing
    def osm_update_accuracy(self, accuracy):
        if not isinstance(accuracy, float):
            accuracy = float(accuracy)
        self.accuracy = accuracy
    def osm_update_geoBounds_extrapolated(self, geoBounds, most_propable_heading, rect_name):
        geo_attr = (geoBounds, most_propable_heading, rect_name)
        self.geoBoundsExtrapolated.append(geo_attr)
    def osm_update_geoBounds(self, geoBounds, most_propable_heading, rect_name, clear=False):
        if clear:
            self.geoBounds.clear()
        geo_attr = (geoBounds, most_propable_heading, rect_name)
        self.geoBounds.append(geo_attr)
    def draw_center(self, *args, **kwargs):
        if self.centerLat is None or self.centerLng is None:
            self.print_log_line(f'Unable to render Center position. No coordinates available', log_level='Warning')
            return
        self.map_layout.map_view.lon = self.centerLng
        self.map_layout.map_view.lat = self.centerLat
        if self.first_start:
            self.map_layout.map_view.zoom = 15
        if self.first_start or self.map_layout.map_view.re_center:
            self.map_layout.map_view.center_on(self.centerLat, self.centerLng)
        if self.first_start:
            self.first_start = False
        for m in self.markers:
            self.map_layout.map_view.remove_marker(m)
        self.markers.clear()
        marker = MapMarker(lon=self.centerLng, lat=self.centerLat, source=CAR_ICON)
        self.markers.append(marker)
        self.map_layout.map_view.add_marker(marker)
    def draw_routing_control(self, f_handle, pois, route_calc):
        if pois is not None:
            if route_calc:
                self.print_log_line('Calculate shortest route to POI %s' % str(pois))
    def draw_geoBounds(self, *args, **kwargs):
        color_index = 0
        if Maps.TRIGGER_RECT_DRAW:
            for geoBounds in self.geoBounds:
                if isinstance(geoBounds[0][0][0], float) and isinstance(geoBounds[0][0][1], float) and isinstance(geoBounds[0][1][0], float) and isinstance(geoBounds[0][1][1], float):
                    self.print_log_line(' Rectangles available for drawing')
                    p0 = geoBounds[0][0][0]
                    p1 = geoBounds[0][0][1]
                    p2 = geoBounds[0][1][0]
                    p3 = geoBounds[0][1][1]
                    coordinattes = [p0, p1, p2, p3]
                    line_layer = LineMapLayer(coordinattes, color_index, self.map_layout.map_view, self.line_layers)
                    self.line_layers.append(line_layer)
                    self.map_layout.map_view.add_layer(line_layer)
                    self.print_log_line('Draw lines!')
                    Clock.schedule_once(line_layer.draw_lines, 0)
                color_index += 1
            Maps.TRIGGER_RECT_DRAW = False
        if self.extrapolated:
            if Maps.TRIGGER_RECT_DRAW_EXTRAPOLATED:
                for geoBounds in self.geoBoundsExtrapolated:
                    if isinstance(geoBounds[0][0][0], float) and isinstance(geoBounds[0][0][1], float) and isinstance(geoBounds[0][1][0], float) and isinstance(geoBounds[0][1][1], float):
                        p0 = geoBounds[0][0][0]
                        p1 = geoBounds[0][0][1]
                        p2 = geoBounds[0][1][0]
                        p3 = geoBounds[0][1][1]
                        coordinattes = [p0, p1, p2, p3]
                        line_layer = LineMapLayer(coordinattes, color_index, self.map_layout.map_view, self.line_layers)
                        self.line_layers.append(line_layer)
                        self.map_layout.map_view.add_layer(line_layer)
                        self.print_log_line('Draw lines!')
                        Clock.schedule_once(line_layer.draw_lines, 0)
                Maps.TRIGGER_RECT_DRAW_EXTRAPOLATED = False
    def draw_pois(self, *args, **kwargs):
        if OSMThread.pois_drawn:
            return
        source = None
        amenity = '---'
        city = '---'
        street = '---'
        post_code = '---'
        name = '---'
        phone = '---'
        if OSMThread.POIS is not None and len(OSMThread.POIS) > 0:
            for m in self.markers_pois:
                self.map_layout.map_view.remove_marker(m)
            self.markers_pois.clear()
            for element in OSMThread.POIS:
                try:
                    lat = element['lat']
                    lon = element['lon']
                except KeyError:
                    continue
                if 'tags' in element:
                    try:
                        amenity = element['tags']['amenity']
                    except KeyError:
                        pass
                    try:
                        city = element['tags']['addr:city']
                    except KeyError:
                        pass
                    try:
                        post_code = element['tags']['addr:postcode']
                    except KeyError:
                        pass
                    try:
                        street = element['tags']['addr:street']
                    except KeyError:
                        pass
                    try:
                        name = element['tags']['name']
                    except KeyError:
                        pass
                    try:
                        phone = element['tags']['phone']
                    except KeyError:
                        pass
                    if amenity == 'hospital':
                        source = HOSPITAL_ICON
                    elif amenity == 'fuel':
                        source = GAS_ICON
                self.print_log_line('Adding Marker for POIS (%f, %f)' % (lon, lat))
                marker = CustomMarkerPois(self.markers_pois, list(), list(), lon=lon, lat=lat, popup_size=(dp(230), dp(130)), source=POI_MARKER)
                self.markers_pois.append(marker)
                bubble = CustomBubble()
                try:
                    image = CustomAsyncImage(source=source if source else UNDEFINED_ICON, mipmap=True)
                except Exception as e:
                    self.print_log_line(f'Failed to load image {source}: {e}', log_level='WARNING')
                    image = CustomAsyncImage(source=UNDEFINED_ICON, mipmap=True)
                label = CustomLabel(text='', markup=True, halign='center')
                label.update_text(f'[b]{amenity}[/b]', f'{city}', f'{post_code}', f'{street}', f'{name}', f'{phone}')
                box = CustomLayout(orientation='horizontal', padding='5dp')
                box.add_widget(image)
                box.add_widget(label)
                bubble.add_widget(box)
                marker.add_widget(bubble)
                self.map_layout.map_view.add_widget(marker)
            OSMThread.pois_drawn = True
    def draw_speed_cams(self, *args, **kwargs):
        speed_cam_list = self.get_unique_speed_cam_list()
        speed_cam_list_cloud = self.get_unique_speed_cam_list(cloud=True)
        speed_cam_list_db = self.get_unique_speed_cam_list(db=True)
        to_be_drawn = [speed_cam_list, speed_cam_list_cloud, speed_cam_list_db]
        for cameras in to_be_drawn:
            if len(cameras) > 0:
                source = None
                for attributes in cameras:
                    key = attributes[0]
                    coord_0 = attributes[1]
                    coord_1 = attributes[2]
                    name = attributes[3]
                    direction = attributes[4]
                    maxspeed = attributes[5]
                    maxspeed_conditional = attributes[6]
                    description = attributes[7]
                    if key.find('FIX') == 0:
                        source = FIX_ICON
                    elif key.find('TRAFFIC') == 0:
                        source = TRAFFIC_ICON
                    elif key.find('DISTANCE') == 0:
                        source = DISTANCE_ICON
                    else:
                        source = MOBILE_ICON
                    marker = CustomMarkerCams(list(), self.markers_cams, list(), lon=float(coord_1), lat=float(coord_0), popup_size=(dp(230), dp(130)))
                    markers = list(map(lambda m: m.lon == marker.lon and m.lat == marker.lat, self.markers_cams))
                    if any(markers):
                        self.print_log_line(f'Ignore adding marker ({(marker.lat, marker.lon)}), already added into map')
                    try:
                        image = CustomAsyncImage(source=source, mipmap=True)
                    except Exception as e:
                        self.print_log_line(f'Failed to load image {source}: {e}', log_level='WARNING')
                        image = CustomAsyncImage(source=UNDEFINED_ICON, mipmap=True)
                    self.markers_cams.append(marker)
                    bubble = CustomBubble()
                    image = CustomAsyncImage(source=source, mipmap=True)
                    label = CustomLabel(text='', markup=True, halign='center')
                    label.update_text(f'[b]{name}[/b]', f'{direction}', f'{maxspeed}', f'{maxspeed_conditional}', f'{description}')
                    box = CustomLayout(orientation='horizontal', padding='5dp')
                    box.add_widget(image)
                    box.add_widget(label)
                    bubble.add_widget(box)
                    marker.add_widget(bubble)
                    self.map_layout.map_view.add_widget(marker)
        return
    def draw_construction_areas(self, *args, **kwargs):
        construction_areas = self.get_unique_constrcution_areas_list()
        if len(construction_areas) > 0:
            source = CONSTRUCTION_ICON
            for attributes in construction_areas:
                key = attributes[0]
                coord_0 = attributes[1]
                coord_1 = attributes[2]
                construction = attributes[3]
                name = attributes[4]
                surface = attributes[5]
                check_date = attributes[6]
                marker = CustomMarkerConstructionAreas(list(), list(), self.markers_construction_areas, lon=float(coord_1), lat=float(coord_0), popup_size=(dp(230), dp(130)), source=CONSTRUCTION_MARKER)
                markers = list(map(lambda m: m.lon == marker.lon and m.lat == marker.lat, self.markers_construction_areas))
                if any(markers):
                    self.print_log_line(f'Ignore adding marker ({(marker.lat, marker.lon)}), already added into map')
                    continue
                self.print_log_line(f'Adding Marker for Construction Area {key}: ({(marker.lat, marker.lon)})')
                self.markers_construction_areas.append(marker)
                bubble = CustomBubble()
                image = CustomAsyncImage(source=source, mipmap=True)
                label = CustomLabel(text='', markup=True, halign='center')
                label.update_text(f'[b]{construction}[/b]', f'{name}', f'{surface}', f'{check_date}')
                box = CustomLayout(orientation='horizontal', padding='5dp')
                box.add_widget(image)
                box.add_widget(label)
                bubble.add_widget(box)
                marker.add_widget(bubble)
                self.map_layout.map_view.add_widget(marker)
    def remove_marker_from_map(self, lon, lat):
        self.print_log_line(f'Removing Speed camera marker ({(lon, lat)}) from Map')
        markers = list(filter(lambda m: m.lon == lon and m.lat == lat, self.markers_cams))
        if markers:
            for marker_to_delete in markers:
                self.remove_camera_from_calculator_thread(marker_to_delete.lon, marker_to_delete.lat)
                self.map_layout.map_view.remove_marker(marker_to_delete)
                if marker_to_delete in self.markers_cams:
                    self.markers_cams.remove(marker_to_delete)
    def remove_all_construction_markers(self):
        for marker in self.markers_construction_areas:
            self.print_log_line(f'Removing Construction area marker ({(marker.lon, marker.lat)}) from Map')
            self.map_layout.map_view.remove_marker(marker)
            self.markers_construction_areas.remove(marker)
            self.remove_construction_area_from_calculator_thread(marker.lon, marker.lat)
    def remove_construction_area_from_calculator_thread(self, longitude, latitude):
        if self.calculator is not None:
            for construction_d in self.calculator.construction_areas:
                for key, entry in construction_d.items():
                    lat = entry[2]
                    lon = entry[3]
                    if lat == latitude and lon == longitude:
                        self.print_log_line(f'Removing construction area ({(lat, lon)}) from RectangleCalculatorThread')
                        self.calculator.construction_areas.remove(construction_d)
                        self.calculator.update_kivi_info_page(update_construction_areas=True, mode='DECREASE')
    def remove_camera_from_calculator_thread(self, longitude, latitude):
        if self.calculator is not None:
            for speed_cam_d in self.calculator.speed_cam_dict:
                for key, entry in speed_cam_d.items():
                    lat = entry[2]
                    lon = entry[3]
                    if lat == latitude and lon == longitude:
                        self.print_log_line(f'Removing camera ({(lat, lon)}) from RectangleCalculatorThread')
                        self.calculator.speed_cam_dict.remove(speed_cam_d)
    def get_unique_constrcution_areas_list(self):
        construction_areas = []
        processing_cams = self.map_queue.consume_construction(self.cv_map_construction)
        self.cv_map_construction.release()
        for i in range(0, len(processing_cams)):
            for key, attributes in processing_cams[i].items():
                construction_areas.append((key, attributes[0], attributes[1], attributes[7] if len(attributes) >= 8 else '---', attributes[8] if len(attributes) >= 9 else '---', attributes[9] if len(attributes) >= 10 else '---', attributes[10] if len(attributes) >= 11 else '---'))
        return list(set(construction_areas))
    def get_unique_speed_cam_list(self, cloud=False, db=False):
        speed_cams = []
        if db:
            processing_cams = self.map_queue.consume_db(self.cv_map_db)
            self.cv_map_db.release()
        else:
            processing_cams = self.map_queue.consume_osm(self.cv_map_osm) if not cloud else self.map_queue.consume_cloud(self.cv_map_cloud)
            if cloud:
                self.cv_map_cloud.release()
            else:
                self.cv_map_osm.release()
        for i in range(0, len(processing_cams)):
            for key, attributes in processing_cams[i].items():
                speed_cams.append((key, attributes[0], attributes[1], attributes[7] if len(attributes) >= 8 else '---', attributes[8] if len(attributes) >= 9 else '---', attributes[9] if len(attributes) >= 10 else '--- Km/h', attributes[10] if len(attributes) >= 11 else '@ Always', attributes[11] if len(attributes) >= 12 else '---'))
        return list(set(speed_cams))
    def initLocation(self, f_handle, geo_rectangle_available):
        f_handle.write('\t\tfunction onLocationInit() {\n')
        f_handle.write('\t\t\tmarkers.clearLayers();\n')
        f_handle.write('\t\t\tvar radius = %f / 2;\n' % self.accuracy)
        f_handle.write('\n')
        f_handle.write('\t\t\t// add layers\n')
        f_handle.write('\t\t\t//L.control.layers(baseLayers,overlays).addTo(map);\n')
        f_handle.write('\t\t\t//L.control.scale().addTo(map);\n')
        f_handle.write('\n')
        f_handle.write('\t\t\tmarker.bindPopup("CCP within " + radius + " meters from " + %f + "," + %f + ", Heading: %s");\n' % (self.centerLat, self.centerLng, self.heading))
        f_handle.write('\n')
        f_handle.write('\t\t\t//define gps cycle\n')
        f_handle.write('\t\t\tcircle = L.circle([%f,%f], radius);\n' % (self.centerLat, self.centerLng))
        f_handle.write('\n')
        f_handle.write('\t\t\tmarkers.addLayer(marker);\n')
        f_handle.write('\t\t\tmarkers.addLayer(circle);\n')
        f_handle.write('\t\t\tmarkers.addTo(map);\n')
        f_handle.write('\t\t\tmap.setView(new L.LatLng(%f,%f), map.getZoom());\n' % (self.centerLat, self.centerLng))
        f_handle.write('\t\t\twindow.location.reload();\n')
        f_handle.write('\n')
        f_handle.write('\t\t}\n')
        f_handle.write('\n')
    def updateZoom(self, f_handle):
        f_handle.write('\t\tfunction updateZoom() {\n')
        f_handle.write('\t\t\tL.DomEvent.on(map.getContainer(), "mousewheel", function() {zoom = map.getZoom()});\n')
        f_handle.write('\t\t\tmap.setZoom(zoom);\n')
        f_handle.write('\n')
        f_handle.write('\t\t}\n')
        f_handle.write('\n\n')
    def updateLocation(self, f_handle, geo_rectangle_available):
        f_handle.write('\t\tfunction updateLocation() {\n')
        f_handle.write('\t\t\tmarkers.clearLayers();\n')
        f_handle.write('\t\t\tvar radius = %f / 2;\n' % self.accuracy)
        f_handle.write('\n')
        f_handle.write('\t\t\tmarker.bindPopup("CCP within " + radius + " meters from " + %f + "," + %f + ", Heading: %s");\n' % (self.centerLat, self.centerLng, self.heading))
        f_handle.write('\n')
        f_handle.write('\t\t\t//define gps cycle\n')
        f_handle.write('\t\t\tcircle = L.circle([%f,%f], radius);\n' % (self.centerLat, self.centerLng))
        f_handle.write('\n')
        f_handle.write('\t\t\tmarkers.addLayer(marker);\n')
        f_handle.write('\t\t\tmarkers.addLayer(circle);\n')
        f_handle.write('\t\t\tmarkers.addTo(map);\n')
        f_handle.write('\t\t\tmap.setView(new L.LatLng(%f,%f), zoom);\n' % (self.centerLat, self.centerLng))
        f_handle.write('\t\t\tmap.setZoom(zoom);\n')
        f_handle.write('\t\t\twindow.location.reload();\n')
        f_handle.write('\n')
        f_handle.write('\t\t}\n')
        f_handle.write('\n\n')
    def draw_map(self, geo_rectangle_available=False):
        Clock.schedule_once(partial(self.draw_center))
        if geo_rectangle_available and self.draw_rects:
            pass
        Clock.schedule_once(partial(self.draw_speed_cams))
        Clock.schedule_once(partial(self.draw_construction_areas))
        if OSMThread.trigger == 'DRAW_POIS':
            Clock.schedule_once(partial(self.draw_pois))
        return True
