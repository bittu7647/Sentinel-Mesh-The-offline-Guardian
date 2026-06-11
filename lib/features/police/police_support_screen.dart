import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/places_service.dart';

class PoliceSupportScreen extends StatefulWidget {
  const PoliceSupportScreen({super.key});

  @override
  State<PoliceSupportScreen> createState() => _PoliceSupportScreenState();
}

class _PoliceSupportScreenState extends State<PoliceSupportScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  List<dynamic> _stations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPlaces();
  }

  Future<void> _fetchPlaces() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));

      final results = await PlacesService.getNearbyPoliceStations(pos.latitude, pos.longitude);
      setState(() {
        _stations = results;
        _isLoading = false;
      });

      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14));
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.colorDeepGreen,
      appBar: AppBar(
        title: const Text("POLICE SUPPORT"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          if (_currentLocation != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _currentLocation!, zoom: 14),
              myLocationEnabled: true,
              markers: _stations.map((s) => Marker(
                markerId: MarkerId(s['place_id']),
                position: LatLng(s['geometry']['location']['lat'], s['geometry']['location']['lng']),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
              )).toSet(),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 190,
              margin: const EdgeInsets.only(bottom: 32),
              child: _isLoading
                ? _buildSkeletonList()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: _stations.length,
                    itemBuilder: (context, index) => _buildPlaceCard(_stations[index]),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: AppColors.colorSurface.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(28)),
      ),
    );
  }

  Widget _buildPlaceCard(dynamic place) {
    final double distance = Geolocator.distanceBetween(
      _currentLocation!.latitude, _currentLocation!.longitude,
      place['geometry']['location']['lat'], place['geometry']['location']['lng']
    );
    final String distanceText = "${(distance / 1000).toStringAsFixed(1)} km";

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.colorSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.colorAquaMint.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place['name'], style: AppTextStyles.labelLarge.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(distanceText, style: AppTextStyles.bodySmall.copyWith(color: AppColors.colorAquaMint)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _launchNav(place['geometry']['location']['lat'], place['geometry']['location']['lng']),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.colorAquaMint,
                foregroundColor: AppColors.colorDeepGreen,
                shape: const StadiumBorder(),
              ),
              child: const Text("NAVIGATE"),
            ),
          ),
        ],
      ),
    );
  }

  void _launchNav(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }
}
