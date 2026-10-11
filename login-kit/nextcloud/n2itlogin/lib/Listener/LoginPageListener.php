<?php
declare(strict_types=1);

namespace OCA\N2itLogin\Listener;

use OCA\N2itLogin\AppInfo\Application;
use OCP\AppFramework\Http\Events\BeforeLoginTemplateRenderedEvent;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\Util;

/** @template-implements IEventListener<BeforeLoginTemplateRenderedEvent> */
class LoginPageListener implements IEventListener {
	public function handle(Event $event): void {
		if (!$event instanceof BeforeLoginTemplateRenderedEvent) {
			return;
		}
		Util::addStyle(Application::APP_ID, 'n2it-login');
		Util::addScript(Application::APP_ID, 'n2it-login');
	}
}
