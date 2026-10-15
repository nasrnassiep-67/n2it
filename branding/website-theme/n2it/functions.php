<?php
/**
 * N2IT child theme for Twenty Twenty-Five.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'N2IT_THEME_VERSION', '2.0.0' );

require_once __DIR__ . '/inc/forms.php';
require_once __DIR__ . '/inc/turnstile.php';

/* Styles: parent first, then ours (cache-busted by file time so edits show at once). */
add_action( 'wp_enqueue_scripts', function () {
	$css = get_stylesheet_directory() . '/assets/css/n2it.css';
	wp_enqueue_style( 'n2it', get_stylesheet_directory_uri() . '/assets/css/n2it.css', array(), (string) @filemtime( $css ) );
} );
add_action( 'after_setup_theme', function () {
	add_editor_style( 'assets/css/n2it.css' );
} );

/* Pattern category for the N2IT sections. */
add_action( 'init', function () {
	register_block_pattern_category( 'n2it', array( 'label' => __( 'N2IT', 'n2it' ) ) );
} );

/* [n2it_year] - current year for the footer copyright line. */
add_shortcode( 'n2it_year', function () {
	return esc_html( wp_date( 'Y' ) );
} );

/* [n2it_asset path="img/x.webp"] - URL of a theme asset, for use inside patterns and pages. */
add_shortcode( 'n2it_asset', function ( $atts ) {
	$atts = shortcode_atts( array( 'path' => '' ), $atts );
	return esc_url( get_stylesheet_directory_uri() . '/assets/' . ltrim( $atts['path'], '/' ) );
} );

/* Small hardening and clean-up. */
add_filter( 'xmlrpc_enabled', '__return_false' );
remove_action( 'wp_head', 'wp_generator' );
remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
remove_action( 'wp_print_styles', 'print_emoji_styles' );
add_filter( 'the_generator', '__return_empty_string' );

/* Mail sent by the site comes from a proper website address. */
add_filter( 'wp_mail_from', function () {
	return 'website@n2it.co.za';
} );
add_filter( 'wp_mail_from_name', function () {
	return 'N2IT Website';
} );

/* wp-login.php: same look as the panel and webmail logins. */
add_action( 'login_enqueue_scripts', function () {
	$css = get_stylesheet_directory() . '/assets/css/login.css';
	wp_enqueue_style( 'n2it-login', get_stylesheet_directory_uri() . '/assets/css/login.css', array( 'login' ), (string) @filemtime( $css ) );
} );
add_filter( 'login_headerurl', function () {
	return home_url( '/' );
} );
add_filter( 'login_headertext', function () {
	return 'N2IT Solutions';
} );
add_filter( 'login_display_language_dropdown', '__return_false' );
add_action( 'login_footer', function () {
	echo '<div id="n2it_app_links"><div class="apps">'
		. '<a href="https://cpl-jhb.nextel.co.za:2096/" title="N2IT Webmail"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4.2-8 5-8-5V6l8 5 8-5v2.2z"/></svg>Email</a>'
		. '<a href="' . esc_url( home_url( '/email-web-hosting/' ) ) . '" title="N2IT Web Hosting"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.9a15.7 15.7 0 0 0-1.4-3.6A8 8 0 0 1 18.9 8zM12 4c.8 1.2 1.5 2.5 1.9 4h-3.8c.4-1.5 1.1-2.8 1.9-4zM4.3 14a8.2 8.2 0 0 1 0-4h3.4a16.5 16.5 0 0 0 0 4H4.3zm.8 2h2.9c.3 1.3.8 2.5 1.4 3.6A8 8 0 0 1 5.1 16zM8 8H5.1a8 8 0 0 1 4.3-3.6C8.8 5.5 8.3 6.7 8 8zm4 12c-.8-1.2-1.5-2.5-1.9-4h3.8c-.4 1.5-1.1 2.8-1.9 4zm2.3-6H9.7a14.7 14.7 0 0 1 0-4h4.6a14.7 14.7 0 0 1 0 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h2.9a8 8 0 0 1-4.3 3.6zM16.3 14a16.5 16.5 0 0 0 0-4h3.4a8.2 8.2 0 0 1 0 4h-3.4z"/></svg>Web Hosting</a>'
		. '</div></div>';
} );
