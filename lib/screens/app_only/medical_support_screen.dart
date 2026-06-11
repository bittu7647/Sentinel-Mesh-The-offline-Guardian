import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/places_service.dart';
import '../../theme/app_theme.dart';

class MedicalSupportScreen extends StatefulWidget {
  const MedicalSupportScreen({super.key});

  @override
  State<MedicalSupportScreen> createState() => _MedicalSupportScreenState();
}

class _MedicalSupportScreenState extends State<MedicalSupportScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  List<dynamic> _hospitals = [];
  Set<Marker> _markers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLocationAndPlaces();
  }

  Future<void> _fetchLocationAndPlaces() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      final hospitals = await PlacesService.getNearbyHospitals(
        position.latitude, position.longitude,
        forcedTimeout: const Duration(seconds: 25),
      );

      if (hospitals.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No hospitals found nearby. Please try again later."),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      Set<Marker> newMarkers = {};
      newMarkers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );

      for (var hospital in hospitals) {
        final lat = hospital['geometry']['location']['lat'];
        final lng = hospital['geometry']['location']['lng'];
        newMarkers.add(
          Marker(
            markerId: MarkerId(hospital['place_id']),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: hospital['name']),
          )
        );
      }

      setState(() {
        _hospitals = hospitals;
        _markers = newMarkers;
        _isLoading = false;
      });

      if (_mapController != null && _currentLocation != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 14.0));
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint("Error fetching location/places: $e");
    }
  }

  Future<void> _callAmbulance(String? phone) async {
    final url = phone != null ? 'tel:$phone' : 'tel:108'; // India ambulance
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<void> _navigate(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  String _calculateETA(double lat, double lng) {
    if (_currentLocation == null) return "N/A";
    double distanceInMeters = Geolocator.distanceBetween(
      _currentLocation!.latitude, _currentLocation!.longitude,
      lat, lng
    );
    double distanceInKm = distanceInMeters / 1000;
    // ~40 km/h urban average for emergency vehicles
    int etaMinutes = (distanceInKm / 40 * 60).ceil();
    return "~$etaMinutes min ETA";
  }

  String _formatDistance(double lat, double lng) {
    if (_currentLocation == null) return "N/A";
    double distanceInMeters = Geolocator.distanceBetween(
      _currentLocation!.latitude, _currentLocation!.longitude,
      lat, lng
    );
    return "${(distanceInMeters / 1000).toStringAsFixed(1)} km";
  }

  Widget _buildPlaceCard(dynamic place) {
    final lat = place['geometry']['location']['lat'];
    final lng = place['geometry']['location']['lng'];
    
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.accentRose.withValues(alpha: 0.1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.accentRose.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.local_hospital_rounded, color: AppTheme.accentRose, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  place['name'] ?? 'Hospital',
                  style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w800, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDistance(lat, lng), style: const TextStyle(color: AppTheme.textDim, fontSize: 14, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentRose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _calculateETA(lat, lng), 
                  style: const TextStyle(color: AppTheme.accentRose, fontSize: 12, fontWeight: FontWeight.w800)
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _callAmbulance(place['phone']),
                  icon: const Icon(Icons.phone_rounded, size: 16),
                  label: const Text('CALL'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.bg,
                    foregroundColor: AppTheme.textMain,
                    side: BorderSide(color: AppTheme.textDim.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _navigate(lat, lng),
                  icon: const Icon(Icons.near_me_rounded, size: 16),
                  label: const Text('NAV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentRose,
                    foregroundColor: AppTheme.bg,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Container(width: 150, height: 16, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4))),
            ],
          ),
          const Spacer(),
          Container(width: 80, height: 12, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Container(height: 40, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)))),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 40, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)))),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('MEDICAL SUPPORT'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textMain, size: 20), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded, color: AppTheme.accentRose),
            onPressed: () => _callAmbulance(null),
          )
        ],
      ),
      body: Stack(
        children: [
          if (_currentLocation != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentLocation!,
                zoom: 14.0,
              ),
              markers: _markers,
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            )
          else
            const Center(child: CircularProgressIndicator(color: AppTheme.accentRose)),
          
          // BOTTOM SUGGESTIONS
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 190,
              margin: const EdgeInsets.only(bottom: 32),
              child: _isLoading
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    itemBuilder: (context, index) => _buildSkeletonCard(),
                  )
                : _hospitals.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: _hospitals.length,
                      itemBuilder: (context, index) {
                        return _buildPlaceCard(_hospitals[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
