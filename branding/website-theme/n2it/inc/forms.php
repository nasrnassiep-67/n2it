<?php
/**
 * N2IT contact and support forms.
 *
 *   [n2it_form type="contact"]  -> info@n2it.co.za
 *   [n2it_form type="ticket"]   -> helpdesk@n2it.co.za
 *
 * Every submission is also stored as a private "Enquiry" in wp-admin, so nothing is lost if mail fails.
 * Spam protection: nonce, hidden honeypot field, minimum fill time, and 5 submissions per hour per IP.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function n2it_form_config() {
	return array(
		'contact' => array(
			'to'      => 'info@n2it.co.za',
			'subject' => 'Website enquiry',
		),
		'ticket'  => array(
			'to'      => 'helpdesk@n2it.co.za',
			'subject' => 'Support ticket',
		),
	);
}

function n2it_form_topics() {
	return array(
		'Connectivity / Internet',
		'Email & Web Hosting',
		'Cloud Hosting & Computing',
		'Telephony / PBX',
		'Networking & WiFi',
		'Firewall & Security',
		'CCTV & Access Control',
		'Website Development',
		'Becoming a Reseller',
		'Account Query',
		'Other',
	);
}

/* Private post type that keeps a copy of every submission. */
add_action( 'init', function () {
	register_post_type( 'n2it_enquiry', array(
		'labels'          => array(
			'name'          => __( 'Enquiries', 'n2it' ),
			'singular_name' => __( 'Enquiry', 'n2it' ),
		),
		'public'          => false,
		'show_ui'         => true,
		'show_in_menu'    => true,
		'menu_icon'       => 'dashicons-email-alt',
		'menu_position'   => 25,
		'supports'        => array( 'title', 'editor' ),
		'capability_type' => 'post',
		'capabilities'    => array( 'create_posts' => 'do_not_allow' ),
		'map_meta_cap'    => true,
	) );
} );

function n2it_client_ip() {
	$ip = $_SERVER['REMOTE_ADDR'] ?? '';
	if ( ! empty( $_SERVER['HTTP_CF_CONNECTING_IP'] ) ) {
		$ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
	}
	return filter_var( $ip, FILTER_VALIDATE_IP ) ? $ip : '0.0.0.0';
}

/* One line, no header-injection characters. */
function n2it_clean_line( $value, $max = 200 ) {
	$value = sanitize_text_field( wp_unslash( (string) $value ) );
	$value = str_replace( array( "\r", "\n", '%0a', '%0d' ), ' ', $value );
	return mb_substr( $value, 0, $max );
}

add_shortcode( 'n2it_form', function ( $atts ) {
	$atts = shortcode_atts( array( 'type' => 'contact' ), $atts );
	$type = array_key_exists( $atts['type'], n2it_form_config() ) ? $atts['type'] : 'contact';

	$status = isset( $_GET['n2it_form'] ) ? sanitize_key( $_GET['n2it_form'] ) : '';
	$out    = '<div class="n2it-form-wrap" id="n2it-form">';

	if ( 'sent' === $status ) {
		$out .= '<div class="n2it-notice n2it-notice--ok" role="status"><strong>' . esc_html__( 'Thank you - your message has been sent.', 'n2it' ) . '</strong> ';
		$out .= 'ticket' === $type
			? esc_html__( 'Our support team will be in touch shortly.', 'n2it' )
			: esc_html__( 'A member of our team will get back to you within one business day.', 'n2it' );
		$out .= '</div></div>';
		return $out;
	}
	if ( $status ) {
		$messages = array(
			'missing' => __( 'Please fill in all the required fields.', 'n2it' ),
			'email'   => __( 'Please enter a valid email address.', 'n2it' ),
			'limit'   => __( 'Too many messages from your connection. Please try again later or call us on 010 007 0891.', 'n2it' ),
			'expired' => __( 'The form expired. Please try again.', 'n2it' ),
			'bot'     => __( 'Please complete the security check and try again.', 'n2it' ),
			'mail'    => __( 'Your message was saved, but our mail system did not accept it. Please also call us on 010 007 0891.', 'n2it' ),
		);
		$msg  = $messages[ $status ] ?? $messages['expired'];
		$out .= '<div class="n2it-notice n2it-notice--err" role="alert">' . esc_html( $msg ) . '</div>';
	}

	$out .= '<form class="n2it-form" method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '">';
	$out .= wp_nonce_field( 'n2it_form_' . $type, '_n2it_nonce', true, false );
	$out .= '<input type="hidden" name="action" value="n2it_form">';
	$out .= '<input type="hidden" name="type" value="' . esc_attr( $type ) . '">';
	$out .= '<input type="hidden" name="ts" value="' . esc_attr( time() ) . '">';
	$out .= '<input type="hidden" name="back" value="' . esc_attr( get_permalink() ) . '">';
	$out .= '<div class="n2it-hp" aria-hidden="true"><label>Website <input type="text" name="website" tabindex="-1" autocomplete="off"></label></div>';

	$out .= '<div class="n2it-form__row">';
	$out .= '<p><label for="n2it-name">' . esc_html__( 'Full name', 'n2it' ) . ' <span>*</span></label><input id="n2it-name" type="text" name="name" required maxlength="120" autocomplete="name"></p>';
	$out .= '<p><label for="n2it-company">' . esc_html__( 'Company', 'n2it' ) . '</label><input id="n2it-company" type="text" name="company" maxlength="120" autocomplete="organization"></p>';
	$out .= '</div><div class="n2it-form__row">';
	$out .= '<p><label for="n2it-email">' . esc_html__( 'Email address', 'n2it' ) . ' <span>*</span></label><input id="n2it-email" type="email" name="email" required maxlength="160" autocomplete="email"></p>';
	$out .= '<p><label for="n2it-phone">' . esc_html__( 'Phone number', 'n2it' ) . ( 'contact' === $type ? ' <span>*</span>' : '' ) . '</label><input id="n2it-phone" type="tel" name="phone" maxlength="40" autocomplete="tel"' . ( 'contact' === $type ? ' required' : '' ) . '></p>';
	$out .= '</div>';

	if ( 'contact' === $type ) {
		$out .= '<div class="n2it-form__row">';
		$out .= '<p><label for="n2it-topic">' . esc_html__( 'What can we help with?', 'n2it' ) . '</label><select id="n2it-topic" name="topic">';
		foreach ( n2it_form_topics() as $topic ) {
			$out .= '<option>' . esc_html( $topic ) . '</option>';
		}
		$out .= '</select></p>';
		$out .= '<p><span class="n2it-label">' . esc_html__( 'Request a call back?', 'n2it' ) . '</span><span class="n2it-radios"><label><input type="radio" name="callback" value="Yes"> ' . esc_html__( 'Yes', 'n2it' ) . '</label><label><input type="radio" name="callback" value="No" checked> ' . esc_html__( 'No', 'n2it' ) . '</label></span></p>';
		$out .= '</div>';
	} else {
		$out .= '<p><label for="n2it-subject">' . esc_html__( 'Subject', 'n2it' ) . ' <span>*</span></label><input id="n2it-subject" type="text" name="subject" required maxlength="160" placeholder="' . esc_attr__( 'A short summary of the issue', 'n2it' ) . '"></p>';
	}

	$out .= '<p><label for="n2it-message">' . esc_html__( 'Message', 'n2it' ) . ' <span>*</span></label><textarea id="n2it-message" name="message" rows="6" required maxlength="5000"' . ( 'ticket' === $type ? ' placeholder="' . esc_attr__( 'Describe the issue in as much detail as possible: what happened, when it started, and who is affected.', 'n2it' ) . '"' : '' ) . '></textarea></p>';
	$out .= apply_filters( 'n2it_form_extra_fields', '' );
	$out .= '<p class="n2it-form__privacy">' . sprintf(
		/* translators: %s: privacy policy link */
		esc_html__( 'We only use your details to respond to this message. See our %s.', 'n2it' ),
		'<a href="/privacy/" target="_blank" rel="noopener">' . esc_html__( 'privacy policy', 'n2it' ) . '</a>'
	) . '</p>';
	$out .= '<p><button type="submit" class="wp-element-button">' . ( 'ticket' === $type ? esc_html__( 'Log ticket', 'n2it' ) : esc_html__( 'Send message', 'n2it' ) ) . '</button></p>';
	$out .= '</form></div>';

	return $out;
} );

function n2it_handle_form() {
	$config = n2it_form_config();
	$type   = isset( $_POST['type'] ) ? sanitize_key( $_POST['type'] ) : '';
	$back   = isset( $_POST['back'] ) ? esc_url_raw( wp_unslash( $_POST['back'] ) ) : home_url( '/' );
	$back   = wp_validate_redirect( $back, home_url( '/' ) );
	$go     = function ( $status ) use ( $back ) {
		wp_safe_redirect( add_query_arg( 'n2it_form', $status, $back ) . '#n2it-form' );
		exit;
	};

	if ( ! isset( $config[ $type ] ) || ! wp_verify_nonce( $_POST['_n2it_nonce'] ?? '', 'n2it_form_' . $type ) ) {
		$go( 'expired' );
	}
	// Bots: filled honeypot or submitted in under 3 seconds -> pretend success, send nothing.
	$ts = (int) ( $_POST['ts'] ?? 0 );
	if ( ! empty( $_POST['website'] ) || ( time() - $ts ) < 3 ) {
		$go( 'sent' );
	}

	if ( ! apply_filters( 'n2it_form_human_check', true ) ) {
		$go( 'bot' );
	}

	$ip  = n2it_client_ip();
	$key = 'n2it_form_' . md5( $ip );
	$cnt = (int) get_transient( $key );
	if ( $cnt >= 5 ) {
		$go( 'limit' );
	}

	$f = array(
		'name'     => n2it_clean_line( $_POST['name'] ?? '', 120 ),
		'company'  => n2it_clean_line( $_POST['company'] ?? '', 120 ),
		'email'    => sanitize_email( wp_unslash( $_POST['email'] ?? '' ) ),
		'phone'    => n2it_clean_line( $_POST['phone'] ?? '', 40 ),
		'topic'    => n2it_clean_line( $_POST['topic'] ?? '', 80 ),
		'callback' => n2it_clean_line( $_POST['callback'] ?? '', 5 ),
		'subject'  => n2it_clean_line( $_POST['subject'] ?? '', 160 ),
		'message'  => mb_substr( sanitize_textarea_field( wp_unslash( $_POST['message'] ?? '' ) ), 0, 5000 ),
	);
	if ( 'contact' === $type && ! in_array( $f['topic'], n2it_form_topics(), true ) ) {
		$f['topic'] = 'Other';
	}

	$required = 'ticket' === $type ? array( 'name', 'email', 'subject', 'message' ) : array( 'name', 'email', 'phone', 'message' );
	foreach ( $required as $r ) {
		if ( '' === $f[ $r ] ) {
			$go( 'missing' );
		}
	}
	if ( ! is_email( $f['email'] ) ) {
		$go( 'email' );
	}
	set_transient( $key, $cnt + 1, HOUR_IN_SECONDS );

	$subject = 'ticket' === $type
		? sprintf( '[Support] %s - %s', $f['subject'], $f['name'] )
		: sprintf( '[Website] %s - %s', $f['topic'], $f['name'] );

	$lines = array(
		'Name'        => $f['name'],
		'Company'     => $f['company'],
		'Email'       => $f['email'],
		'Phone'       => $f['phone'],
		'Topic'       => 'contact' === $type ? $f['topic'] : '',
		'Call back'   => 'contact' === $type ? $f['callback'] : '',
		'Subject'     => 'ticket' === $type ? $f['subject'] : '',
		'Page'        => $back,
		'IP address'  => $ip,
	);
	$body = '';
	foreach ( $lines as $label => $value ) {
		if ( '' !== $value ) {
			$body .= str_pad( $label . ':', 13 ) . $value . "\n";
		}
	}
	$body .= "\n" . $f['message'] . "\n";

	wp_insert_post( array(
		'post_type'    => 'n2it_enquiry',
		'post_status'  => 'private',
		'post_title'   => $subject,
		'post_content' => $body,
	) );

	$headers = array( 'Reply-To: ' . $f['name'] . ' <' . $f['email'] . '>' );
	$sent    = wp_mail( $config[ $type ]['to'], $subject, $body, $headers );

	$go( $sent ? 'sent' : 'mail' );
}
add_action( 'admin_post_n2it_form', 'n2it_handle_form' );
add_action( 'admin_post_nopriv_n2it_form', 'n2it_handle_form' );
