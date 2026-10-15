<?php
/**
 * Cloudflare Turnstile bot check on wp-login (login + lost password) and the N2IT contact/support forms.
 *
 * Keys live in wp-config.php: N2IT_TURNSTILE_SITE and N2IT_TURNSTILE_SECRET (copy in /root/n2it-turnstile.env).
 * Remove or rename those two constants to switch the check off (e.g. if you are ever locked out).
 * The check is verified on the server, so it also applies to bots that bypass Cloudflare and hit the server IP.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function n2it_turnstile_enabled() {
	return defined( 'N2IT_TURNSTILE_SITE' ) && defined( 'N2IT_TURNSTILE_SECRET' ) && N2IT_TURNSTILE_SITE && N2IT_TURNSTILE_SECRET;
}

function n2it_turnstile_widget() {
	return '<div class="cf-turnstile n2it-turnstile" data-sitekey="' . esc_attr( N2IT_TURNSTILE_SITE ) . '" data-theme="light" data-size="flexible"></div>';
}

function n2it_turnstile_script() {
	wp_enqueue_script( 'cf-turnstile', 'https://challenges.cloudflare.com/turnstile/v0/api.js', array(), null, array( 'strategy' => 'defer' ) );
}

/**
 * Returns true if the posted Turnstile token is valid.
 * If Cloudflare cannot be reached at all, the check is skipped (logged) so staff are never locked out by an outage.
 */
function n2it_turnstile_verify() {
	$token = isset( $_POST['cf-turnstile-response'] ) ? sanitize_text_field( wp_unslash( $_POST['cf-turnstile-response'] ) ) : '';
	if ( '' === $token ) {
		return false;
	}
	$res = wp_remote_post( 'https://challenges.cloudflare.com/turnstile/v0/siteverify', array(
		'timeout' => 8,
		'body'    => array(
			'secret'   => N2IT_TURNSTILE_SECRET,
			'response' => $token,
			'remoteip' => function_exists( 'n2it_client_ip' ) ? n2it_client_ip() : ( $_SERVER['REMOTE_ADDR'] ?? '' ),
		),
	) );
	if ( is_wp_error( $res ) || 200 !== wp_remote_retrieve_response_code( $res ) ) {
		error_log( 'N2IT Turnstile: Cloudflare unreachable, check skipped: ' . ( is_wp_error( $res ) ? $res->get_error_message() : wp_remote_retrieve_response_code( $res ) ) );
		return true;
	}
	$body = json_decode( wp_remote_retrieve_body( $res ), true );
	return ! empty( $body['success'] );
}

if ( ! n2it_turnstile_enabled() ) {
	return;
}

/* ---- wp-login.php ---- */
add_action( 'login_enqueue_scripts', 'n2it_turnstile_script' );
add_action( 'login_form', function () {
	echo n2it_turnstile_widget(); // phpcs:ignore WordPress.Security.EscapeOutput -- escaped in the function
} );
add_action( 'lostpassword_form', function () {
	echo n2it_turnstile_widget(); // phpcs:ignore WordPress.Security.EscapeOutput
} );

// Login: runs after the username/password check (priority 20). Only for the wp-login.php form itself.
add_filter( 'authenticate', function ( $user ) {
	if ( 'POST' !== ( $_SERVER['REQUEST_METHOD'] ?? '' ) || ( $GLOBALS['pagenow'] ?? '' ) !== 'wp-login.php' || ! isset( $_POST['log'] ) ) {
		return $user;
	}
	if ( ! n2it_turnstile_verify() ) {
		return new WP_Error( 'n2it_turnstile', __( '<strong>Error:</strong> Please complete the security check and try again.', 'n2it' ) );
	}
	return $user;
}, 30 );

add_action( 'lostpassword_post', function ( $errors ) {
	if ( ! n2it_turnstile_verify() ) {
		$errors->add( 'n2it_turnstile', __( '<strong>Error:</strong> Please complete the security check and try again.', 'n2it' ) );
	}
} );

/* ---- N2IT contact / support forms (inc/forms.php) ---- */
add_filter( 'n2it_form_extra_fields', function ( $html ) {
	n2it_turnstile_script();
	return $html . '<p>' . n2it_turnstile_widget() . '</p>';
} );
add_filter( 'n2it_form_human_check', function ( $ok ) {
	return $ok && n2it_turnstile_verify();
} );
