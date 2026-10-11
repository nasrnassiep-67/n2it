<?php
declare(strict_types=1);

namespace OCA\N2itLogin\Listener;

use OCP\AppFramework\Http\ContentSecurityPolicy;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\IRequest;
use OCP\Security\CSP\AddContentSecurityPolicyEvent;

/**
 * Lets the Cloudflare Turnstile widget load, on the login page only.
 * @template-implements IEventListener<AddContentSecurityPolicyEvent>
 */
class CspListener implements IEventListener {
	public function __construct(
		private IRequest $request,
	) {
	}

	public function handle(Event $event): void {
		if (!$event instanceof AddContentSecurityPolicyEvent) {
			return;
		}
		if (!preg_match('#^/login(/|$)#', (string)$this->request->getPathInfo())) {
			return;
		}
		$policy = new ContentSecurityPolicy();
		$policy->addAllowedScriptDomain('https://challenges.cloudflare.com');
		$policy->addAllowedFrameDomain('https://challenges.cloudflare.com');
		$policy->addAllowedConnectDomain('https://challenges.cloudflare.com');
		$event->addPolicy($policy);
	}
}
