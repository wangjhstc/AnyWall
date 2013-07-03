//
//  PAWLoginViewController.m
//  Anywall
//
//  Created by Christopher Bowns on 2/1/12.
//  Copyright (c) 2013 Parse. All rights reserved.
//

#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoa/EXTScope.h>
#import <Parse-RACExtensions/PFUser+RACExtensions.h>

#import "PAWLoginViewController.h"

#import "PAWAppDelegate.h"
#import <Parse/Parse.h>
#import "PAWActivityView.h"
#import "PAWWallViewController.h"

static NSString * const PAWLoginErrorDomain = @"PAWLoginErrorDomain";
static const NSUInteger PAWGenericErrorCode = 1;

static NSString * const PAWFirstResponderKey = @"PAWFirstResponderKey";

@implementation PAWLoginViewController

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

	@weakify(self);

	// Hijack the button's action.
	self.doneButton.rac_command = [RACCommand command];

	// Bind the button's enabled property to a signal indicating whether all
	// required fields have been filled. If any field is empty, the signal sends
	// @NO, thus disabling the button.
	//
	// This would normally be done for us by +commandWithCanExecuteSignal:, but
	// this controller calls the command's -execute: in -textFieldShouldReturn:,
	// and to preserve existing behavior, the command needs to execute even when
	// required fields are missing.
	RAC(self.doneButton.enabled) = [[[RACSignal
		combineLatest:@[
			self.usernameField.rac_textSignal,
			self.passwordField.rac_textSignal,
		]]
		map:^(RACTuple *fieldValues) {
			return @([fieldValues.rac_sequence all:^BOOL (NSString *text) {
				return text.length > 0;
			}]);
		}]
		startWith:@NO];

	// Defines the action that will execute whenever the button is tapped.
	RACSignal *logInAction = [self.doneButton.rac_command addActionBlock:^(id sender) {
		__block PAWActivityView *activityView = nil;

		return [[[[RACSignal
			defer:^{
				@strongify(self);

				// +defer: used only for initial subscription side effects.
				// In this case, for updating the UI to indicate busy state.
				[self resignFirstResponder];
				activityView = [self presentActivityView];

				// These signals send errors for failed validation.
				return [RACSignal combineLatest:@[ [self validatedUsername], [self validatedPassword] ]];
			}]
			flattenMap:^(RACTuple *credentials) {
				RACTupleUnpack(NSString *username, NSString *password) = credentials;

				// Call to +[PFUser loginWithUsername:password:] encapsulated in a signal.
				return [PFUser rac_logInWithUsername:username password:password];
			}]
			finally:^{
				@strongify(self);

				// Tear down busy state UI.
				[self dismissActivityView:activityView];
			}]
			deliverOn:RACScheduler.mainThreadScheduler];
	}];

	// Handle the results of log in using the results from the latest action.
	[self rac_liftSelector:@selector(logInDidSucceed:) withSignals:[logInAction switchToLatest], nil];

	// Commands have a separate errors signal. Using the errors signal allows us
	// to keep error handling localized, and outside of the "happy path".
	[self rac_liftSelector:@selector(logInFailed:) withSignals:self.doneButton.rac_command.errors, nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.usernameField becomeFirstResponder];
}

#pragma mark - IBActions

- (IBAction)cancel:(id)sender {
	[self.presentingViewController dismissModalViewControllerAnimated:YES];
}

#pragma mark - UITextFieldDelegate methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField == self.usernameField) {
		[self.passwordField becomeFirstResponder];
	}
	if (textField == self.passwordField) {
		[self.passwordField resignFirstResponder];
		[self.doneButton.rac_command execute:textField];
	}

	return YES;
}

#pragma mark - Private methods:

#pragma mark - Response Handling

- (void)logInDidSucceed:(PFUser *)user {
	PAWWallViewController *wallViewController = [[PAWWallViewController alloc] initWithNibName:nil bundle:nil];
	[(UINavigationController *)self.presentingViewController pushViewController:wallViewController animated:NO];
	[self.presentingViewController dismissModalViewControllerAnimated:YES];
}

- (void)logInFailed:(NSError *)error {
	UIAlertView *alert = [UIAlertView new];
	alert.title = error.localizedRecoverySuggestion ?: error.localizedFailureReason;
	[alert addButtonWithTitle:NSLocalizedString(@"Ok", nil)];
	[alert show];

	UIResponder *responder = error.userInfo[PAWFirstResponderKey] ?: self.usernameField;
	[responder becomeFirstResponder];
}

#pragma mark - Signals

- (RACSignal *)validatedUsername {
	if (self.usernameField.text.length == 0) {
		return [RACSignal error:[self errorWithRecoverySuggestion:NSLocalizedString(@"No username entered", nil) responder:self.usernameField]];
	}

	return [RACSignal return:self.usernameField.text];
}

- (RACSignal *)validatedPassword {
	if (self.passwordField.text.length == 0) {
		return [RACSignal error:[self errorWithRecoverySuggestion:NSLocalizedString(@"No password entered", nil) responder:self.passwordField]];
	}

	return [RACSignal return:self.passwordField.text];
}

#pragma mark - User Interface

- (PAWActivityView *)presentActivityView {
	PAWActivityView *activityView = [[PAWActivityView alloc] initWithFrame:CGRectMake(0.f, 0.f, self.view.frame.size.width, self.view.frame.size.height)];
	UILabel *label = activityView.label;
	label.text = NSLocalizedString(@"Logging In", nil);
	label.font = [UIFont boldSystemFontOfSize:20.f];
	[activityView.activityIndicator startAnimating];
	[activityView layoutSubviews];

	[self.view addSubview:activityView];

	return activityView;
}

- (void)dismissActivityView:(PAWActivityView *)activityView {
	[activityView.activityIndicator stopAnimating];
	[activityView removeFromSuperview];
}

#pragma mark - Errors

- (NSError *)errorWithRecoverySuggestion:(NSString *)suggestion responder:(UIResponder *)responder {
	return [NSError errorWithDomain:PAWLoginErrorDomain code:PAWGenericErrorCode userInfo:@{
		NSLocalizedRecoverySuggestionErrorKey: suggestion,
		PAWFirstResponderKey: responder,
	}];
}

@end
