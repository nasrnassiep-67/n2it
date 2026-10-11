<?php
declare(strict_types=1);

namespace OCA\N2itLogin\AppInfo;

use OCA\N2itLogin\Listener\CspListener;
use OCA\N2itLogin\Listener\LoginPageListener;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\AppFramework\Http\Events\BeforeLoginTemplateRenderedEvent;
use OCP\Security\CSP\AddContentSecurityPolicyEvent;

class Application extends App implements IBootstrap {
	public const APP_ID = 'n2itlogin';

	public function __construct() {
		parent::__construct(self::APP_ID);
	}

	public function register(IRegistrationContext $context): void {
		$context->registerEventListener(BeforeLoginTemplateRenderedEvent::class, LoginPageListener::class);
		$context->registerEventListener(AddContentSecurityPolicyEvent::class, CspListener::class);
	}

	public function boot(IBootContext $context): void {
	}
}
